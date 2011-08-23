%define name mint-utils
%define version 0.0.1
%define release 1

Summary: MINT utility scripts
Name: %{name}
Version: %{version}
Release: %{release}
Source0: %{name}_%{version}.orig.tar.gz
License: GPLv2+
Group: Development/Tools/Building
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Prefix: %{_prefix}
BuildArch: noarch
Vendor: Islam Amer <islam.amer@nokia.com>
Url: https://github.com/iamer/useful-scripts

Requires: osc
Requires: git

%description
MINT utility scripts send_to_OBS and project_status.

%prep
%setup -q -n %{name}-%{version}

%build
make

%install
rm -rf $RPM_BUILD_ROOT
make DESTDIR=%{buildroot} install

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
/usr/bin/*

%changelog
* Tue Aug 23 2011 Islam Amer <islam.amer@nokia.com> 0.0.1
- Initial packaging
