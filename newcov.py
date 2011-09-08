#! /usr/bin/python

# newcov - list new code that is not covered by the unit tests

import optparse
import os
import re
import subprocess
import sys

def parsecommandline(argv):
    parser = optparse.OptionParser(usage='%prog [options]')

    parser.add_option('-b', '--base', type='string', dest='base',
        metavar='<commit or branch>',
        help='Base to diff from, defaults to branch point from master')
    parser.add_option('-f', '--file', type='string', dest='file',
        metavar='<coveragefile>',
        help='Name of the file containing the coverage report. Default is to '
             'generate the report by running the unit tests.')

    (options, _) = parser.parse_args(argv)
    return options

def read_and_print(command, outf=sys.stdout):
    """Run a shell command and collect the output file printing it."""
    process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE)
    output = []
    for line in process.stdout:
        output.append(line)
        #outf.write(line)
    return ''.join(output)

def find_merge_base(commitspec=None):
    """Find the best common ancestor between the working tree and base."""
    if commitspec:
        command = ['git', 'merge-base', 'HEAD', commitspec]
    else:
        command = ['git', 'merge-base', 'HEAD', 'master', 'origin/master']
    process = subprocess.Popen(command, stdout=subprocess.PIPE)
    (output, _) = process.communicate()
    return output.split()[0]

def get_diff(fromcommit):
    command = ['git', 'diff', fromcommit]
    process = subprocess.Popen(command, stdout=subprocess.PIPE)
    (output, _) = process.communicate()
    return output

def parse_coverage_report(report):
    """Return a list of (filename, [linenr]) with data from this report."""
    delim = None
    started = False
    results = []
    for line in report.splitlines():
        line = line.strip()
        if line == delim:
            if not started:
                started = True
                continue
            else:
                return results
        if not started:
            if line.startswith('Name ') and line.endswith(' Missing'):
                delim = '-' * len(line)
            continue
        fields = line.split(None, 4)
        modulename = fields[0]
        filename = os.path.join(*modulename.split('.')) + '.py'
        linenrs = []
        if len(fields) > 4:
            for chunk in fields[4].split():
                if chunk.endswith(','):
                    chunk = chunk[:-1]
                if '-' in chunk:
                    first, last = chunk.split('-')
                    linenrs.extend(range(int(first), int(last)+1))
                else:
                    linenrs.append(int(chunk))
        results.append((filename, linenrs))
    return results

def find_new_lines(diff):
    filename = None
    linenr = 0
    results = []
    lines = []
    for line in diff.splitlines():
        if line.startswith('+++ '):
            if filename:
                results.append((filename, lines))
                lines = []
            filename = line[6:]  # cut off "--- a/"
            linenr = 0
        elif line.startswith('@@ '):
            matchobj = re.match(r'^@@ -\d+(,\d+)? \+(\d+)(,\d+)? @@', line)
            linenr = int(matchobj.group(2))
        elif line.startswith('+'):
            lines.append(linenr)
            linenr += 1
        elif line.startswith(' '):
            linenr += 1
    if filename:
        results.append((filename, lines))
    return results

def compact_lines(linenrs):
    last = None
    in_run = False
    results = []
    for linenr in linenrs:
        if linenr - 1 == last:
            in_run = True
        else:
            if in_run:
                in_run = False
                results[-1] = "%s-%d" % (results[-1], last)
            results.append(str(linenr))
        last = linenr
    if in_run:
        results[-1] = "%s-%d" % (results[-1], last)
    return ', '.join(results)

def main(options):
    base = find_merge_base(options.base)

    if options.file:
        with open(options.file) as inf:
            report = inf.read()
    else:
        report = read_and_print("python runtests.py")

    coveredlines = parse_coverage_report(report)
    diff = get_diff(base)
    newcode = find_new_lines(diff)

    cdict = dict(coveredlines)
    reportlines = []
    for filename, lines in newcode:
        if not filename.endswith('.py'):
            continue
        if filename not in cdict:
            uncovered_lines = []
        else:
            uncovered_lines = [linenr for linenr in cdict[filename]
                               if linenr in lines]
        reportlines.append((filename, uncovered_lines))
    width = max([len(filename) for filename, _ in reportlines])
    total = 0
    for filename, lines in reportlines:
        if lines:
            print "%s %s" % (filename.ljust(width+2), compact_lines(lines))
            total += len(lines)
    print "%d new lines not covered" % total

if __name__ == '__main__':
    sys.exit(main(parsecommandline(sys.argv)))
