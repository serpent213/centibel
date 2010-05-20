#!/usr/bin/env ruby

# centiBel : media player
#
# System image builder
#
# == Synopsis 
#   This script creates a flash image file containing the player operating system.
#   Requires the ArchLinux package manager (pacman).
#
# == Usage 
#   builder.rb [options]
#
#   For help, use: builder.rb -h
#
# == Options
#   -o, --output FILENAME            Set target image filename
#   -s, --size BYTES                 Set target image size
#                                    (append "m" for 10^6, "g" for 10^9)
#   -h, --help                       Display help (including defaults)
#       --version                    Display version info
#       --manual                     Display this manual
#
# == Author
#   Steffen Beyer <serpent@centibel.org>
#   <http://www.centibel.org/>
#
# == Copyright
#   Copyright 2010 Steffen Beyer.

require 'rubygems'

require 'fileutils'
require 'optparse'
# require 'rdoc/usage'
require 'readline'
require 'term/ansicolor'
require 'tmpdir'

include Term::ANSIColor

##### helper subroutines #####

def section(title)
  puts '', bold(black("*** #{title} ***")), ''
end

def continue?
  puts
  begin
    line = Readline.readline cyan('continue (y/[n])? ')
  end until ['y', 'n', ''].any? { |w| w == line }

  exit 2 unless line == 'y'
end

##### main program #####

# set defaults

options = {}
options[:image_filename]  = 'centibel.img'
options[:image_size]      = 2 * 10 ** 9

# parse command line

OptionParser.new do |opts|
  opts.version = "0.4.0"
  opts.release = "2010-02-20"

  opts.banner = "Usage: builder.rb [options]"

  opts.separator ""
  opts.separator "Specific options:"

  opts.on("-o", "--output FILENAME", "Set target image filename (default \"#{options[:image_filename]}\")") do |b|
    options[:image_filename] = b
  end
  opts.on("-s", "--size BYTES", "Set target image size (default #{options[:image_size] / 10**6}MB)") do |b|
    options[:image_size] = b
  end
  opts.on("--manual", "Display manual") do
    puts opts.ver
    RDoc::usage
  end
end.parse!

puts white + bold + 'centiBel : media player -- system image builder' + reset

if m = options[:image_size].to_s.match(/^(\d+)([mg]?)$/i)
  capacity_bytes = m[1].to_i * ({ 'm' => 10**6, 'g' => 10**9 }[m[2].downcase] || 1)
else
  raise 'cannot interpret target image size'
end

# leave 5% headroom to compensate for various models of flash memory
#capacity_MiB = (capacity_bytes / 2**20/ 1.05).round
capacity_MiB = (capacity_bytes / 2**20).round

ROOT_PWD_CRYPT  = '$1$XFCrfQHD$ZZoCa1Myqo1cGBMmPYOcH.'   # "centibel"
QT_DISTRIBUTION = 'qt-everywhere-opensource-src-4.6.2'

# check for root uid
raise 'must run as root' unless Process.uid == 0

# find pacman executable
if system('which pacman.static >/dev/null 2>&1')
  pacman = 'pacman.static'
elsif system('which pacman >/dev/null 2>&1')
  pacman = 'pacman'
else
  raise 'pacman not found in path -- maybe run prepare_host.rb?'
end

section 'creating empty image file (may take a while)'

if File.exists? options[:image_filename]
  puts "WARNING: output file \"#{options[:image_filename]}\" will be overwritten"
  continue?
end

system "dd if=/dev/zero of=#{options[:image_filename]} bs=1024k count=#{capacity_MiB}"

section 'setting up filesystem'

# find free loopback device
lodevice = `losetup -f`.chomp

begin
  # set up loopback device
  system "losetup #{lodevice} #{options[:image_filename]}"

  # calculate number of "cylinders" assuming 255 heads, 63 sectors/track and 512 bytes/sector
  track_bytes = 255 * 63 * 512
  cylinders = capacity_MiB * 2 ** 20 / track_bytes

  # create a Linux partition spanning the whole disk, beginning at sector 63
  system "echo 63 | sfdisk --force --Linux -C #{cylinders} -uS #{lodevice}"

  # find free loopback device for the partition
  lopartition = `losetup -f`.chomp

  begin
    # set up loopback device for the partition
    # partition start is fixed (see above)
    # size derived from cylinder count minus start
    start_bytes = 63 * 512
    # TODO Ubuntu doesn't like the short options, ArchLinux doesn't like the long ones...
    system "losetup --offset #{start_bytes} --sizelimit #{cylinders * track_bytes - start_bytes} #{lopartition} #{options[:image_filename]}"

    # create an ext2 filesystem
    system "mke2fs -L centibel #{lopartition}"

    Dir.mktmpdir do |target_dir|
      begin
        system "mount #{lopartition} #{target_dir}"

        section 'invoking pacman to install base packages'

        FileUtils.mkdir_p "#{target_dir}/var/lib/pacman"
        system "#{pacman} -Sy -r #{target_dir} --noconfirm base"

        section 'recreating device nodes'

        Dir.chdir "#{target_dir}/dev" do
          system 'rm console ; mknod -m 600 console c 5 1'
          system 'rm null ; mknod -m 666 null c 1 3'
          system 'rm zero ; mknod -m 666 zero c 1 5'
        end

        section 'transferring host configuration'

        FileUtils.copy '/etc/resolv.conf', "#{target_dir}/etc/resolv.conf"
        FileUtils.copy '/etc/pacman.d/mirrorlist', "#{target_dir}/etc/pacman.d/mirrorlist"

        begin
          section 'mounting pseudo filesystems in target system'

          system "mount -o bind /dev #{target_dir}/dev"
          system "mount -t proc none #{target_dir}/proc"
          system "mount -o bind /sys #{target_dir}/sys"
          # use pacman cache on host
          system "mount -o bind /var/cache/pacman/pkg #{target_dir}/var/cache/pacman/pkg"

          # create a directory on host for building and mount it into the target system
          # we don't want this to happen in the image file
          # TODO use a fixed build dir, keep downloaded packages for reuse
          Dir.mktmpdir do |build_dir|
            begin
              Dir.mkdir "#{target_dir}/tmp/build"
              system "mount -o bind #{build_dir} #{target_dir}/tmp/build"

              # save config files for later use in child process
              config_dir = "#{File.dirname $0}/../conf"

              lilo_config           = File.read "#{config_dir}/lilo.conf"
              rc_config             = File.read "#{config_dir}/rc.conf"
              uvesafb_config        = File.read "#{config_dir}/uvesafb.conf"
              ts_config             = File.read "#{config_dir}/ts.conf"
              tslib_profile         = File.read "#{config_dir}/tslib.sh"
              qtembedded_profile    = File.read "#{config_dir}/qtembedded.sh"

              # (copy player files)

              # create chrooted child
              fork do
                Dir.chroot target_dir

                section 'configuring system'

                # some tools rely on the mtab file
                system 'grep -v rootfs /proc/mounts > /etc/mtab'

                File.open('/etc/fstab', 'a')                            { |f| f.puts '/dev/sda1 / ext2 noatime 0 1' }
                File.open('/etc/ld.so.conf.d/local.conf', 'w')          { |f| f.puts '/usr/local/lib' }

                File.open('/etc/locale.gen', 'a') do |f|
                  f.puts 'en_GB.UTF-8 UTF-8'
                  f.puts 'en_GB ISO-8859-1'
                end
                system 'locale-gen'

                section 'installing additional packages'

                # TODO collect package names somewhere else, alphabetically, commented
                #system 'pacman -Sy --noconfirm lilo base-devel openssh cmake git smbclient qt mpd ruby ruby-mpd kdebindings-smoke bsd-games'
                system 'pacman -Sy --noconfirm lilo base-devel crda v86d zsh vim openssh ntp fbset fbgrab cmake git smbclient alsa-utils mpd ruby ruby-mpd bsd-games'

                section 'downloading and building tslib'

                Dir.chdir '/tmp/build'
                # we use our own SVN snapshot here
                system 'wget http://www.centibel.org/files/lib/tslib-r84.tar.bz2'
                system 'tar xjf tslib-r84.tar.bz2'
                Dir.chdir 'tslib'
                system './configure && make && make install'

                if true
                  section 'downloading and building Qt/Embedded'
                  puts 'time to fetch some coffee...', ''

                  Dir.chdir '/tmp/build'
                  system "wget http://get.qt.nokia.com/qt/source/#{QT_DISTRIBUTION}.tar.gz"
                  system "tar xzf #{QT_DISTRIBUTION}.tar.gz"
                  Dir.chdir QT_DISTRIBUTION
                  system './configure -prefix /usr/local -embedded -opensource -confirm-license -qt-mouse-tslib'
                  system 'make && make install'
                end

                section 'downloading and building QtRuby'

                Dir.chdir '/tmp/build'
                # we use our own (patched) SVN snapshot here
                system 'wget http://www.centibel.org/files/lib/qtruby-20100315.tar.bz2'
                system 'tar xjf qtruby-20100315.tar.bz2'
                Dir.chdir 'kdebindings'

                # symlink is necessary for build to succeed (found on
                # <http://rubyforge.org/forum/forum.php?thread_id=42757&forum_id=723>)
                #File.symlink '../i686-linux/ruby/config.h', '/usr/include/ruby-1.9.1/ruby/config.h'

                # system '/bin/bash -i'

		system './build-ruby19.sh'
		system 'make install'

                section 'finalising configuration'

                File.open('/etc/rc.conf', 'w')                          { |f| f.write rc_config }

                shell_profile = File.read '/etc/profile'
                # append "local" bin directories to path
                shell_profile.sub! /^(\s*PATH=).*/, '\1"/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin"'
                File.open('/etc/profile', 'w')                          { |f| f.write shell_profile }

                # uvesafb
                # based on <http://wiki.archlinux.org/index.php/Uvesafb>
                File.open('/etc/modprobe.d/uvesafb.conf', 'w')          { |f| f.write uvesafb_config }
                mkinitcpio_config = File.read '/etc/mkinitcpio.conf'
                # insert v86d hook after udev
                mkinitcpio_config.sub! /^(\s*HOOKS=.*?udev)/, '\1 v86d'
                File.open('/etc/mkinitcpio.conf', 'w')                  { |f| f.write mkinitcpio_config }
                # TODO breaks the default kernel, disabled for now -- run manually after boot
                # system 'mkinitcpio -p kernel26'

                # tslib
                File.open('/etc/ts.conf', 'w')                          { |f| f.write ts_config }
                File.open('/etc/profile.d/tslib.sh', 'w', 0755)         { |f| f.write tslib_profile }

                # Qt/Embedded
                File.open('/etc/profile.d/qtembedded.sh', 'w', 0755)    { |f| f.write qtembedded_profile }

                File.open('/etc/lilo.conf', 'w')                        { |f| f.write lilo_config }
                system 'lilo'
                # TODO patch lilo.conf for later use on target (keep only boot=...)

                system "usermod -p '#{ROOT_PWD_CRYPT}' root"

                # TODO zsh setup

                # everyone is blocked by default, but we want ssh to work
                File.unlink '/etc/hosts.deny'

                # system 'df -h'
              end

              # wait for child
              Process.wait
            ensure
              Dir.chdir '/'
              system "umount #{target_dir}/tmp/build"
            end
          end
        ensure
          system "umount #{target_dir}/var/cache/pacman/pkg"
          system "umount #{target_dir}/sys"
          system "umount #{target_dir}/proc"
          system "umount #{target_dir}/dev"
        end
      ensure
        # unmount image
        system "umount #{lopartition}"
      end
    end
  ensure
    # release loopback device for the partition
    system "losetup -d #{lopartition}"
  end
ensure
  # release loopback device
  system "losetup -d #{lodevice}"
end

section 'done'
