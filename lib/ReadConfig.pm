#! /usr/bin/perl -w

# Read the config file ('etc/config') and set up some useful variables.
# Exports some useful functions, too.
#
# Usage:
#
#   use ReadConfig;
#
#   exported functions:
#     Print2File(file_name, print_args);
#     SUSystem(command);
#
#   exported arrays:
#     %ConfigData
#
#   exported variables:
#     $Script, $BasePath, $LibPath, $BinPath, $CfgPath, $ImagePath,
#     $DataPath, $TmpBase, $MToolsCfg, $AutoBuild
#
#   symbols *not* exported by default:
#     $SUBinary, DebugInfo

=head1 ReadConfig

C<ReadConfig> is a perl module that reads config data from C<etc/config>
initializes a few global variables and exports some useful functions. It
should always be included in scripts operating within the C<bootdisk>
directory hierarchy.

It assumes that the script that included this library was either called from
the base directory or from the C<bin> subdirectory of the base directory.
The base directory itself may be located anywhere.

This is mainly to avoid an environment variable to hold the base directory
(like C<BOOTDISK_ROOT> or something similar).

For the curious: the regular expression used to find the base directory name
from the full script name is:

C<( $0 =~ /(.*?)((?<![^\/])bin\/)?([^\/]+)$/ )[0]>

=head2 Usage

C<BEGIN { unshift @INC, ( $0 =~ /(.*?)((?<![^\/])bin\/)?[^\/]+$/ )[0] . "lib" }>

C<use ReadConfig;>

=head2 Description

=over

=item *

C<Print2File(file_name, print_args)>

C<Print2File(file_name, print_args)> opens the file C<file_name> and prints
to it. C<print_args> are the arguments that would be given to a normal
C<print> command. It's mainly for convenience.

=for html <p>

=item *

C<SUSystem(command)>

C<SUSystem(command)> executes C<command> with root permissions. This
requires a special 'C<sudo>' command to be installed that can give you root
privileges without asking for a password. The name of this command is
C</usr/local/sw> and can only be changed by editing the C<ReadConfig.pm>
file.

This allows you to run the bootdisk scripts as a normal user.

If you don't have such a program or are running the scripts as root, C<SUSystem> is
I<identical> to the usual C<system> command.

You can check if this feature is actually available by looking at the
C<$ReadConfig::SUBinary> variable that holds the name of the 'C<sudo>'
command (or C<undef>).

=for html <p>

=item *

C<%ConfigData>

C<%ConfigData> is an hash table that holds the config info read from C<etc/config>.
C<etc/config> is a shell script that may contain I<only> variable assignments.

=for html <p>

=item *

exported variables

=over

=item *

C<$Script> is the name of the script that included this library (without the path).

=item *

C<$BasePath> holds the name of the base directory.

=item *

C<$LibPath = "$BasePath/lib">.

=item *

C<$BinPath = "$BasePath/bin">. The C<PATH> environment variable is
appropriately extended.

=item *

C<$CfgPath = "$BasePath/etc">.

=item *

C<$ImagePath = "$BasePath/images">.

=item *

C<$DataPath = "$BasePath/data">.

=item *

C<$TmpBase> is the name used for temporary file/directory names.

=item *

C<$MToolsCfg> is the name of a temporary C<mtools> config file. The
C<MTOOLSRC> environment variable is set to point to it.

=back

=for html <p>

=item *

symbols that are not exported

=over

=item *

C<DebugInfo()> prints the current values of some variables.

=item *

C<$SUBinary> (see C<SUSystem> above).

=back

=back

=cut


package ReadConfig;

require Exporter;
@ISA = qw ( Exporter );
@EXPORT = qw (
  $Script $BasePath $LibPath $BinPath $CfgPath $ImagePath $DataPath
  $TmpBase %ConfigData ReadFile RealRPM ReadRPM $SUBinary SUSystem Print2File $MToolsCfg $AutoBuild
);

use strict 'vars';
use vars qw (
  $Script $BasePath $LibPath $BinPath $CfgPath $ImagePath $DataPath
  $TmpBase %ConfigData $SUBinary &RPMFileName &SUSystem &Print2File $MToolsCfg $AutoBuild
  $rpmData
);

use Cwd;
use File::Path 'make_path';
use File::Spec 'abs2rel';

sub get_repo_list;
sub read_meta;
sub read_packages;


sub DebugInfo
{
  local $_;

  print "Script = \"$Script\"\n";
  print "BasePath = \"$BasePath\"\n";
  print "LibPath = \"$LibPath\"\n";
  print "BinPath = \"$BinPath\"\n";
  print "CfgPath = \"$CfgPath\"\n";
  print "ImagePath = \"$ImagePath\"\n";
  print "DataPath = \"$DataPath\"\n";
  print "TmpBase = \"$TmpBase\"\n";
  print "MToolsCfg = \"$MToolsCfg\"\n";

  print "ConfigData:\n";
  for (sort keys %ConfigData) {
    print "  $_ = \"$ConfigData{$_}\"\n"
  }
}


sub ReadFile
{
  my ($f, $buf);

  open $f, $_[0];
  sysread($f, $buf, -s $_[0]);
  close $f;

  return $buf;
}


#
# Returns hash with 'name' and 'file' keys or undef if package does not
# exist.
#
sub RealRPM
{ 
  local $_;
  my $rpm = shift;
  my ($f, @f, @ff, $p, $back, $n, %n, $r);

  return $rpmData->{$rpm} if exists $rpmData->{$rpm};

  $back = 1 if $rpm =~ s/~$//;

  if($ConfigData{obs}) {
    $p = $rpm;
    $p = "\Q$p";
    $p =~ s/\\\*/([0-9_]+)/g;
    @f = grep { /^$p / } @{$ConfigData{packages}};

    return $rpmData->{$rpm} = undef if @f == 0;

    @f = sort @f;
    # for (@f) { print ">$_<\n"; }
    $f = pop @f;
    $f = pop @f if $back;

    if($f =~ m/^(\S+) (.+)$/) {
      return $rpmData->{$1} = $rpmData->{$rpm} = { name => $1, file => "$ConfigData{tmp_cache_dir}/.obs/$2/$1.rpm", rfile => "../.obs/$2/$1.rpm", obs => "$2" };
    }
    else {
      return $rpmData->{$rpm} = undef;
    }
  }
  else {
    my $dir = $ConfigData{suse_base};

    @f = grep { -f } <$ConfigData{cache_dir}/$rpm.rpm $dir/$rpm.rpm>;
    for (@f) {
      $n = $_;
      s#^.*/|\.rpm$##g;
      $n{$_} = $n unless exists $n{$_};
    }

    return $rpmData->{$rpm} = undef if @f == 0;

    $p = $rpm;
    $p = "\Q$p";
    $p =~ s/\\\*/([0-9_]+)/g;
    @f = grep { /^$p$/ } @f;
    @f = sort @f;
    # for (@f) { print ">$_<\n"; }
    $f = pop @f;
    $f = pop @f if $back;

    return $rpmData->{$f} = $rpmData->{$rpm} = { name => $f, file => $n{$f} } ;
  }
}


#
# 'rpm' is hash as returned from RealRPM().
#
sub UnpackRPM
{
  my $rpm = shift;
  my $dir = shift;
  my ($log, $i);

  return 1 unless $rpm;

  if($rpm->{obs} && ! -f $rpm->{file}) {
    # retry up to 3 times
    for ($i = 0; $i < 3; $i++) {
      $log .= `curl -o '$rpm->{file}' '$ConfigData{obs_server}/build/$rpm->{obs}/$ConfigData{obs_arch}/_repository/$rpm->{name}.rpm' 2>&1`;
      # system "curl -s -o '$rpm->{file}' '$ConfigData{obs_url}/$rpm->{obs}'";
      last if -f $rpm->{file};
    }
    if(! -f $rpm->{file}) {
      print STDERR "$rpm->{file}: $ConfigData{obs_server}/build/$rpm->{obs}/$ConfigData{obs_arch}/_repository/$rpm->{name}.rpm\n" . $log;
      warn "$Script: failed to download $rpm->{name}";
      return 1
    }
  }

  if(SUSystem "sh -c 'cd $dir ; rpm2cpio $rpm->{file} | cpio --quiet --sparse -dimu --no-absolute-filenames'") {
    print STDERR "$rpm->{file}: $ConfigData{obs_server}/build/$rpm->{obs}/$ConfigData{obs_arch}/_repository/$rpm->{name}.rpm\n" . $log;
    warn "$Script: failed to extract $rpm->{name}";
    return 1;
  }

  symlink($rpm->{rfile} ? $rpm->{rfile} : $rpm->{file}, "$ConfigData{tmp_cache_dir}/.rpms/$rpm->{name}.rpm");

  return 0;
}


#
# Unpack rpm to cache dir and return path to dir or undef if failed.
#
sub ReadRPM
{
  local $_;
  my ($s, $f, @s);

  my $rpm = RealRPM $_[0];

  if(!$rpm || !$rpm->{name}) {
    warn "$Script: no such package: $_[0]";
    return undef;
  }

  my $rpm_cmd = "rpm --nosignature";
  my $dir = "$ConfigData{tmp_cache_dir}/$rpm->{name}";
  my $tdir = "$dir/rpm";

  return $dir if -d $dir;

  die "$Script: failed to create $dir ($!)" unless mkdir $dir, 0777;
  die "$Script: failed to create $tdir ($!)" unless mkdir $tdir, 0777;

  my $err = UnpackRPM $rpm, $tdir;

  if(!$err) {
    $_ = `$rpm_cmd -qp --qf '%{VERSION}-%{RELEASE}.%{ARCH}' $rpm->{file} 2>/dev/null`;
    open $f, ">$dir/version";
    print $f $_;
    close $f;

    $_ = `$rpm_cmd -qp --requires $rpm->{file} 2>/dev/null`;
    open $f, ">$dir/requires";
    print $f $_;
    close $f;

    @s = `$rpm_cmd -qp --qf '%|PREIN?{PREIN\n}:{}|%|POSTIN?{POSTIN\n}:{}|%|PREUN?{PREUN\n}:{}|%|POSTUN?{POSTUN\n}:{}|' $rpm->{file} 2>/dev/null`;
    for (@s) {
      chomp;
      $_ = "\L$_";
      $s = `$rpm_cmd -qp --qf '%{\U$_\E}' $rpm->{file} 2>/dev/null`;
      open $f, ">$dir/$_";
      print $f $s;
      close $f;
    }
    if(@s) {
      $s = join ",", @s;
      open $f, ">$dir/scripts";
      print $f "\L$s";
      close $f;
    }
  }

  if(!$err && $rpm->{name} eq $ConfigData{kernel_rpm}) {
    SUSystem "find $tdir -type d -exec chmod a+rx '{}' \\;";

    my $kv;

    $kv = <$tdir/lib/modules/*>;

    if(-d $kv) {
      $kv =~ s#.*/##;
      open $f, ">$dir/kernel";
      print $f $kv;
      close $f;
    }
    else {
      $err = 1;
      undef $kv;
    }

    UnpackRPM RealRPM("$rpm->{name}-base"), $tdir;
    UnpackRPM RealRPM("$rpm->{name}-extra"), $tdir;

    my $kmp;
    for (split(',', $ConfigData{kmp_list})) {
      ($kmp = $rpm->{name}) =~ s/^kernel/$_-kmp/;
      print "adding kmp $kmp\n";
      UnpackRPM RealRPM($kmp), $tdir;
    }

    for (split(',', $ConfigData{fw_list})) {
      print "adding firmware $_\n";
      UnpackRPM RealRPM($_), $tdir;
    }

    # keep it readable
    SUSystem "find $tdir -type d -exec chmod a+rx '{}' \\;";

    # if kmp version differs, copy files to real kernel tree
    for (<$tdir/lib/modules/*>) {
      s#.*/##;
      next if $_ eq $kv;
      print "warning: kmp/firmware version mismatch: $_\n";
      SUSystem "sh -c 'tar -C $tdir/lib/modules/$_ -cf - . | tar -C $tdir/lib/modules/$kv -xf -'";
    }
  }

  return $err ? undef : $dir;
}


#
# execute string as root
#
sub SUSystem
{
  if($SUBinary) {
    return system "$SUBinary -q 0 $_[0]";
  }
  else {
    return system @_;
  }
}

#
# print to a file
#
sub Print2File
{
  local $_ = shift;

  open Print2File_F, ">$_" or return undef;
  print Print2File_F @_;
  close Print2File_F;

  return 1;
}


#
# return list of kernel images
#
sub KernelImg
{
  local $_;
  my ($k_files, @k_images);

  $k_files = shift;

  chomp @$k_files;

  for (@$k_files) {
    s#.*/boot/##;
    next if /autoconf|config|shipped|version/;		# skip obvious garbage
    push @k_images, $_ if m#$ConfigData{kernel_img}#;
  }

  return @k_images;
}


sub version_sort
{
  my ($i, $j);

  $i = $ConfigData{ini}{Version}{$a};
  $j = $ConfigData{ini}{Version}{$b};

  $i =~ s/,([^,]+)//;
  $j =~ s/,([^,]+)//;

  return $i <=> $j;
}


sub get_repo_list
{
  local $_;

  my $prj = shift;
  my $repo = shift;
  my $inrepo;
  my $r = [ ];

  # print "($prj, $repo)\n";

  for (`curl -s '$ConfigData{obs_server}/source/$prj/_meta'`) {
    if($inrepo) {
      if(/<path/) {
        my $x;
        $x->[0] = $1 if /\sproject="([^"]+)"/;
        $x->[1] = $1 if /\srepository="([^"]+)"/;
        push @$r, $x if @$x == 2;
        next;
      }
      elsif(/<\/repository>/) {
        last;
      }
    }
    elsif(/<repository.*\sname="\Q$repo\E"/) {
      $inrepo = 1;
      next;
    }
  }

  # for (@$r) { print "> $_->[0] - $_->[1]\n"; }

  return $r;
}


sub read_meta
{
  local $_;

  my $prj = shift;
  my $repo = shift;
  my $list = [[ $prj, $repo ]];
  my %seen;
  my $cnt;

  do {
    $cnt = 0;
    for (@{get_repo_list(@{$list->[-1]})}) {
      if(!$seen{"$_->[0]/$_->[1]"}) {
        push @$list, $_;
        $cnt++;
      }
      $seen{"$_->[0]/$_->[1]"} = 1;
    }
  } while($cnt);

  # for (@$list) { print ">> $_->[0] - $_->[1]\n"; }

  return $list;
}


sub read_packages
{
  local $_;

  my $prj = shift;
  my $repo = shift;
  my ($list, %seen, $l, @packages, $f, $p, $r);

  if(-f "$ConfigData{tmp_cache_dir}/.obs/packages") {
    open $f, "$ConfigData{tmp_cache_dir}/.obs/packages";
    while(<$f>) {
      chomp;
      push @packages, $_;
    }
    close $f;
    if(@packages) {
      $ConfigData{packages} = [ @packages ];
    }
    else {
      die "no packages in $ConfigData{suse_base}\n";
    }

    return;
  }

  print STDERR "Reading OBS meta data...";

  $list = read_meta($prj, $repo);

  open $f, ">", "$ConfigData{tmp_cache_dir}/.obs/repositories";

  for $l (@$list) {
    $p = $l->[0];
    $r = $l->[1];

    print $f "$p $r\n";
    die "$Script: failed to create $ConfigData{tmp_cache_dir}/.obs/$p/$r ($!)" unless make_path "$ConfigData{tmp_cache_dir}/.obs/$p/$r";

    for (`curl -s '$ConfigData{obs_server}/build/$p/$r/$ConfigData{obs_arch}/_repository?view=binaryversions&nometa=1'`) {
      if(/<binary\s+name="([^"]+)\.rpm"/) {
        push @packages, "$1 $p/$r" unless $seen{$1};
        $seen{$1} = 1;
      }
    }
  }

  close $f;

  # for (@packages) { print "$_\n"; }

  if(@packages) {
    open $f, ">", "$ConfigData{tmp_cache_dir}/.obs/packages";
    for (@packages) { print $f "$_\n" }
    close $f;
    $ConfigData{packages} = [ @packages ];
  }
  else {
    die "no packages in $ConfigData{suse_base}\n";
  }

  print STDERR "\n";
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# initialization part
#

delete $ENV{'LANG'};
delete $ENV{'LANGUAGE'};

if($0 =~ /(.*?)((?<![^\/])bin\/)?([^\/]+)$/) {
  $Script = $3;
  $BasePath = $1;
  $LibPath = $1 . "lib/";
  $BinPath = $1 . "bin/";
  $CfgPath = $1 . "etc/";
  $ImagePath = $1 . "images/";
  $DataPath = $1 . "data/";
}
else {
  die "OOPS: don't invoke the script that way!\n"
}

if(!(
  ($BasePath eq "" || -d $BasePath) &&
  -d $LibPath &&
  -d $BinPath &&
  -d $CfgPath &&
  -d $ImagePath &&
  -d $DataPath
)) {
  die "$Script: you got it all wrong!\n";
}

$| = 1;

$_ = $BinPath;
s:^(.+)/$:$1:;
$ENV{PATH} = "/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/bin:$_";

$TmpBase = "/tmp/${Script}_${$}";
$MToolsCfg = "$TmpBase.mtoolsrc";

$ENV{MTOOLSRC} = $MToolsCfg;

# The purpose of this is to allow to run the scripts without having root
# permissions.
#
# The $SUBinary must be a program that gives you superuser rights *without*
# a password.
#
# If you don't have such a program or *are* already root this feature is
# turned off.

if($<) {	# only if we are *not* already root
  $SUBinary = "/usr/local/bin/sw";
  $SUBinary = "/usr/bin/sw" if -x "/usr/bin/sw";
  $SUBinary = undef unless -x $SUBinary && -u $SUBinary;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# set arch
#

my ($arch, $realarch, $susearch);

$arch = `uname -m`;
chomp $arch;
$arch = "i386" if $arch =~ /^i.86$/;

$arch = $ENV{TEST_ARCH} if exists $ENV{TEST_ARCH};

$realarch = $arch;
$arch = "sparc" if $arch eq 'sparc64';

$susearch = $arch;
$susearch = 'axp' if $arch eq 'alpha';

$ConfigData{arch} = $arch;
$ConfigData{obs_arch} = $arch eq 'i386' ? 'i586' : $arch;


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# read config file & .buildenv
#

{
  my ($f, @f, $sect, $i, $j);

  $f = $CfgPath . "config";
  die "$Script: no config file \"$f\"\n" unless open(F, "$f.$arch") || open(F, $f);

  while(<F>) {
    chomp;
    s/^\s*([#;].*)?//;
    next if $_ eq "";
    if(/^\[(.+)\]/) {
      $sect = $1;
      next;
    }
    if(/^\s*([^=]*?)\s*=\s*(.*?)\s*$/) {
      $ConfigData{ini}{$sect}{$1} = $2 if defined $sect;
      next;
    }
  }

  close F;

  $ConfigData{buildroot} = $ENV{buildroot} ? $ENV{buildroot} : "";

  if(open F, "$ConfigData{buildroot}/.buildenv") {
    while(<F>) {
      chomp;
      s/^\s*([#;].*)?//;
      next if $_ eq "";
      if(/^\s*([^=]*?)\s*=\s*(.*?)\s*$/) {
        $i = $1;
        $j = $2;
        $j = $1 if $j =~ /^\"(.*)\"$/;
        $ConfigData{buildenv}{$i} = $j;
      }
    }
    close F;
  }
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# kernel image name
#

$ConfigData{kernel_img} = $ConfigData{ini}{KernelImage}{default}
  if $ConfigData{ini}{KernelImage}{default};

$ConfigData{kernel_img} = $ConfigData{ini}{KernelImage}{$arch}
  if $ConfigData{ini}{KernelImage}{$arch};

$ConfigData{kernel_img} = $ENV{kernel_img} if $ENV{kernel_img};


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# lib directory
#

$ConfigData{lib} = "lib";
$ConfigData{lib} = $ConfigData{ini}{lib}{default} if $ConfigData{ini}{lib}{default};
$ConfigData{lib} = $ConfigData{ini}{lib}{$arch} if $ConfigData{ini}{lib}{$arch};


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# kernel rpm name
#

$ConfigData{kernel_rpm} = $ConfigData{ini}{KernelRPM}{default}
  if $ConfigData{ini}{KernelRPM}{default};

$ConfigData{kernel_rpm} = $ConfigData{ini}{KernelRPM}{$arch}
  if $ConfigData{ini}{KernelRPM}{$arch};

$ConfigData{kernel_rpm} = $ENV{kernel} if $ENV{kernel};


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# kmp list
#

$ConfigData{kmp_list} = "";

$ConfigData{kmp_list} = $ConfigData{ini}{KMP}{default}
  if $ConfigData{ini}{KMP}{default};

$ConfigData{kmp_list} = $ConfigData{ini}{KMP}{$arch}
  if $ConfigData{ini}{KMP}{$arch};


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# firmware list
#

$ConfigData{fw_list} = "";
$ConfigData{fw_list} = $ConfigData{ini}{Firmware}{default} if $ConfigData{ini}{Firmware}{default};
$ConfigData{fw_list} = $ConfigData{ini}{Firmware}{$arch} if $ConfigData{ini}{Firmware}{$arch};


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


# print STDERR "kernel_rpm = $ConfigData{kernel_rpm}, kernel_img = $ConfigData{kernel_img}\n";

# print STDERR "BUILD_DISTRIBUTION_NAME = $ConfigData{buildenv}{BUILD_DISTRIBUTION_NAME}\n";
# print STDERR "BUILD_BASENAME = $ConfigData{buildenv}{BUILD_BASENAME}\n";


{
  # set suse_base
  # kernel_ver
  # (used to be in etc/config)

  my ( $r, $r0, $rx, $in_abuild, $a, $v, $kv, $rf, $ki, @f );
  my ( $theme, $load_image, $yast_theme, $splash_theme, $product_name, $update_dir);

  my ( $dist, $i, $j );

  $in_abuild = $ConfigData{buildenv}{BUILD_BASENAME} ? 1 : 0;
  $in_abuild = 1 if -d "$ConfigData{buildroot}/.build.binaries";

  # print STDERR "abuild = $in_abuild\n";

  if($in_abuild) {
    my $rpmdir;

    $dist = $ConfigData{buildenv}{BUILD_BASENAME};

    $rpmdir = "$ConfigData{buildroot}/.build.binaries";
    $rpmdir = "$ConfigData{buildroot}/.rpm-cache/$dist" unless -d $rpmdir;

    die "No rpm files found (looking for \"$dist\")!\n" unless -d $rpmdir;

    $ConfigData{suse_base} = $AutoBuild = $rpmdir;
  }
  elsif($ENV{work} || $ENV{dist}) {
    my ($work, $base, $xdist);

    $dist = $susearch;

    $work = $ENV{work} ? $ENV{work} : "/mounts/dist/full";
    $xdist = $ENV{dist} ? $ENV{dist} : "head-$dist";

    if($xdist) {
      $base = "$work/full-$xdist/suse";
      $dist = $xdist if -d $base;
      if(! -d $base) {
        $base = "$work/full-$xdist-$dist/suse";
        $dist = "$xdist-$dist" if -d $base;
      }
    }
    else {
      $base = "$work/full-$dist/suse";
    }

    die "Sorry, could not locate packages for \"$dist\" ($base).\n" unless -d $base;

    $ConfigData{suse_base} = "$base/*";
  }
  else {
    # OBS

    $ConfigData{obs} = 1;

    my ($obs_proj, $obs_repo);

    $ConfigData{obs_proj} = $ConfigData{ini}{OBS}{project};
    $ConfigData{obs_repo} = $ConfigData{ini}{OBS}{repository};
    $ConfigData{obs_server} = $ConfigData{ini}{OBS}{server};

    if($ENV{obs} =~ m#^([^/]+)/([^/]+)-([^/-]+)$#) {
      $ConfigData{obs_proj} = $1;
      $ConfigData{obs_repo} = $2;
      $ConfigData{obs_arch} = $3;
    }

    my ($f, $u, $p, $s);

    if($ConfigData{obs_server} !~ /\@/ && -f "$ENV{HOME}/.oscrc") {
      if($< == 0) {
        # to avoid problems with restrictive .oscrc permissions
        open $f, "su `stat -c %U $ENV{HOME}/.oscrc` -c 'cat $ENV{HOME}/.oscrc' |";
      }
      else {
        open $f, "$ENV{HOME}/.oscrc";
      }
      while(<$f>) {
        undef $s if /^\s*\[/;
        $s = 1 if /^\s*\[\Q$ConfigData{obs_server}\E\/?\]/;
        $u = $1 if $s && /^\s*user\s*=\s*(\S+)/;
        $p = $1 if $s && /^\s*pass\s*=\s*(\S+)/;
      }
      close $f;

      if(defined($u) && defined($p)) {
        $u =~ s/(\W)/sprintf("%%%02X", ord $1)/ge;
        $p =~ s/(\W)/sprintf("%%%02X", ord $1)/ge;
        $ConfigData{obs_server} =~ s#(://)#$1$u:$p@#;
      }
      elsif($ConfigData{obs_server} =~ /^https:/) {
        warn "\nWarning: *** no auth data for $ConfigData{obs_server}! ***\n\n";
        sleep 2;
      }

      # print "$ConfigData{obs_server}\n";
    }

    $ConfigData{obs_url} = "$ConfigData{obs_server}/build/$ConfigData{obs_proj}/$ConfigData{obs_repo}/$ConfigData{obs_arch}/_repository";

    $ConfigData{suse_base} = "$ConfigData{obs_proj}/$ConfigData{obs_repo}-$ConfigData{obs_arch}";

    ($dist = $ConfigData{suse_base}) =~ tr#/#-#;

    # print "$ConfigData{suse_base}\n";
  }

  $ConfigData{dist} = $dist;

  # print STDERR "base = $ConfigData{suse_base}\n";

  $i = $dist;

  $ConfigData{cache_dir} = getcwd() . "/${BasePath}cache/$ConfigData{dist}";
  $ConfigData{tmp_cache_dir} = getcwd() . "/${BasePath}tmp/cache/$ConfigData{dist}";
  system "mkdir -p $ConfigData{tmp_cache_dir}/.rpms" unless -d "$ConfigData{tmp_cache_dir}/.rpms";

  if($ConfigData{obs}) {
    my ($f, @rpms);
    system "mkdir -p $ConfigData{tmp_cache_dir}/.obs" unless -d "$ConfigData{tmp_cache_dir}/.obs";

    read_packages($ConfigData{obs_proj}, $ConfigData{obs_repo});
  }

  my $k_dir = ReadRPM $ConfigData{kernel_rpm};
  if($k_dir) {
    my @k_images = KernelImg [ `find $k_dir/rpm/boot -type f` ];

    if(!@k_images) {
      die "Error: No kernel image identified! (Looking for \"$ConfigData{kernel_img}\".)\n\n";
    }

    if(@k_images != 1) {
      warn "Warning: Can't identify the real kernel image, choosing the first:\n", join(", ", @k_images), "\n\n";
    }

    $ConfigData{kernel_img} = $k_images[0];
    $ConfigData{kernel_ver} = ReadFile "$k_dir/kernel";
    $ConfigData{module_type} = 'ko';
  }

  # print STDERR "kernel_img = $ConfigData{kernel_img}\n";
  # print STDERR "kernel_rpm = $ConfigData{kernel_rpm}\n";
  # print STDERR "kernel_ver = $ConfigData{kernel_ver}\n";

  $theme = $ENV{theme} ? $ENV{theme} : "openSUSE";

  die "Don't know theme \"$theme\"\n" unless exists $ConfigData{ini}{"Theme $theme"};

  if($ENV{themes}) {
    my %t;
    @t{split ' ', $ENV{themes}} = ();
    die "Theme \"$theme\" not supported\n" unless exists $t{$theme};
  }

  $yast_theme = $ConfigData{ini}{"Theme $theme"}{yast};
  $splash_theme = $ConfigData{ini}{"Theme $theme"}{ksplash};
  $product_name = $ConfigData{ini}{"Theme $theme"}{product};
  my $full_product_name = $product_name;
  $full_product_name .= (" " . $ConfigData{ini}{"Theme $theme"}{version}) if $ConfigData{ini}{"Theme $theme"}{version};

  my $suse_release = $ConfigData{ini}{"Theme $theme"}{version};
  my $sle_release = "sle" . $ConfigData{ini}{"Theme $theme"}{sle};
  my $sles_release = "sles" . $ConfigData{ini}{"Theme $theme"}{sle};
  my $sled_release = "sled" . $ConfigData{ini}{"Theme $theme"}{sle};

  $update_dir = $ConfigData{ini}{"Theme $theme"}{update};
  $update_dir =~ s/<sles>/$sles_release/g;
  $update_dir =~ s/<sled>/$sled_release/g;
  $update_dir =~ s/<rel>/$suse_release/g;
  $update_dir =~ s/<arch>/$realarch/g;
  $load_image = $ConfigData{ini}{"Theme $theme"}{image};
  $load_image = $load_image * 1024 if $load_image;

  $ConfigData{theme} = $theme;
  $ConfigData{yast_theme} = $yast_theme;
  $ConfigData{splash_theme} = $splash_theme;
  $ConfigData{product_name} = $product_name;
  $ConfigData{full_product_name} = $full_product_name;
  $ConfigData{update_dir} = $update_dir;
  $ConfigData{load_image} = $load_image;
  $ConfigData{suse_release} = $suse_release;
  $ConfigData{sles_release} = $sles_release;
  $ConfigData{sled_release} = $sled_release;

  $ConfigData{min_memory} = $ConfigData{ini}{"Theme $theme"}{memory};

  # print STDERR "yast_theme = $ConfigData{yast_theme}\n";
  # print STDERR "splash_theme = $ConfigData{splash_theme}\n";
  # print STDERR "product_name = $ConfigData{product_name}\n";
  # print STDERR "update_dir = $ConfigData{update_dir}\n";
  # print STDERR "load_image = $ConfigData{load_image}\n";

  $ConfigData{kernel_mods} = $ConfigData{kernel_ver};
  $ConfigData{kernel_mods} =~ s/-(.+?)-/-override-/;

  $ConfigData{instsys_complain} = $ENV{instsys_complain};
  $ConfigData{instsys_complain_root} = $ENV{instsys_complain_root};
  $ConfigData{instsys_build_id} = $ENV{instsys_build_id};

  if(!$ENV{silent}) {
    my ($r, $kmp);

    if($ConfigData{kmp_list}) {
      $kmp = ' (' . join(', ', map { $_ .= "-kmp" } (split(',', $ConfigData{kmp_list}))) . ')';
    }
    else {
      $kmp = "";
    }

    print "--- Building for $product_name $suse_release $ConfigData{arch} ($sle_release) [$ConfigData{lib}], theme $ConfigData{theme}\n";
    print "--- Kernel: $ConfigData{kernel_rpm}$kmp, $ConfigData{kernel_img}, $ConfigData{kernel_ver}\n";

    $r = $ConfigData{suse_base};
    $r =~ s/\/\*$//;
    print "--- Source: $r\n";
  }
}

1;
