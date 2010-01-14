#!/usr/bin/env ruby

# centiBel : media player

# prepare host system for builder
# downloads and installs ArchLinux packet manager

# Steffen Beyer <serpent@centibel.org>
# <http://www.centibel.org/>

require 'rubygems'

require 'readline'
require 'term/ansicolor'
require 'tmpdir'

include Term::ANSIColor

# helper subroutines

def section title
  puts '', bold(black("*** #{title} ***")), ''
end

def continue?
  puts
  begin
    line = Readline.readline cyan('continue (y/[n])? ')
  end until ['y', 'n', ''].any? { |w| w == line }

  unless line == 'y'
    exit 2
  end
end

# main program

puts white + bold + 'centiBel : media player -- build host preparation' + reset

# check for root uid
raise 'must run as root' unless Process.uid == 0

# pacman already available?
if system('which pacman >/dev/null') || system('which pacman.static >/dev/null')
  puts 'pacman is already installed'
  continue?
end

puts 'WARNING: this script will pollute your base system with a number of files'
puts 'WARNING: automatic deinstallation is not available right now'
continue?

Dir.mktmpdir do |target_dir|
  Dir.chdir target_dir

  section 'downloading packages'

  # URLs taken from <http://wiki.archlinux.org/index.php/Install_from_Existing_Linux>
  system 'wget http://repo.archlinux.fr/i686/pacman-static-3.2.2-1.pkg.tar.gz'
  system 'wget ftp://ftp.archlinux.org/core/os/i686/pacman-\*.pkg.tar.gz'

  section 'extracting packages into base system'

  Dir.chdir '/'
  puts 'errors regarding .PKGINFO can safely be ignored'
  system "for i in #{target_dir}/*.tar.gz ; do tar --keep-old-files -xzf $i ; done"
end

section 'done'

puts 'please edit /etc/pacman.d/mirrorlist now and enable your favourite mirror(s)'
