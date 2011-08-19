#!/usr/bin/perl -w

use strict;
use warnings;
use LWP::UserAgent;
use Data::Dumper;

my $ua = LWP::UserAgent->new;
$ua->agent("$0/0.1 " . $ua->agent);

my %Packages;
my @all;

my @repos = (['home:lbt:MINT', 'http://repo.pub.meego.com/home:/lbt:/MINT/Debian_6.0/Packages'],
	     ['Project:MINT:Devel:BOSS', 'http://repo.pub.meego.com/Project:/MINT:/Devel:/BOSS/Debian_6.0/Packages'],
	     ['Project:MINT:Testing', 'http://repo.pub.meego.com/Project:/MINT:/Testing/Debian_6.0/Packages'],
	    );

foreach my $repo (@repos) {
  my $req = HTTP::Request->new(GET => $repo->[1]);
  $req->header('Accept' => 'text/html');

  # send request
  my $res = $ua->request($req);

  # check the outcome
  my $pkg;
  if ($res->is_success) {
    open my $RH, '<', \$res->decoded_content;
    while (<$RH>) {
      if (/^Package: (.*)$/) {
	$pkg = $1;
	push @all, $pkg;
	next;
      }
      if (/^Version: (.*)$/) {
	$Packages{$repo->[0]}->{$pkg} = $1;
      }
    }
  }
  else {
    print "Error: " . $res->status_line . "\n";
  }
}


printf "%-30s", "Package";
foreach my $repo (@repos) {
  print "\t$repo->[0]";
}
print "\n";

foreach my $pkg (sort @all) {
  printf "%-30s", $pkg;
  foreach my $repo (@repos) {
    print "\t";
    print defined $Packages{$repo->[0]}->{$pkg}?$Packages{$repo->[0]}->{$pkg}:"-";
  }
  print "\n";
}
#print Dumper \%Packages;
