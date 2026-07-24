# RPM spec for the Aurora OS SDUI Playground.
#
# NOTE: verify/regenerate against the Aurora SDK's "Add Aurora project" wizard —
# the exact macro set can differ per SDK version. This is a conventional
# qmake-based Silica app spec (Mer/Sailfish macro lineage).
Name:       ru.auroraos.SduiPlayground
Summary:    SDUI Playground — one JSON contract, native on Aurora
Version:    0.1
Release:    1
License:    MIT
URL:        https://github.com/
Source0:    %{name}-%{version}.tar.bz2

Requires:   sailfishsilica-qt5 >= 0.10.9
BuildRequires:  pkgconfig(auroraapp)
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  desktop-file-utils

%description
The Aurora sibling of the iOS and Android SDUI demos. It renders the same
server-driven JSON screens through a pure-QML/Silica renderer.

%prep
%setup -q -n %{name}-%{version}

%build
%qmake5
%make_build

%install
%qmake5_install

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
# TODO: add launcher icons, then include:
# %{_datadir}/icons/hicolor/*/apps/%{name}.png
