#!/usr/bin/env ruby

# centiBel : media player

# system image builder
# creates a flash image file containing the player operating system
# requires the ArchLinux package manager (pacman)

# Steffen Beyer <serpent@centibel.org>
# <http://www.centibel.org/>

require 'rubygems'

require 'fileutils'
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

puts white + bold + 'centiBel : media player -- system image builder' + reset

filename = 'centibel.img'
# leave 8% headroom to compensate for various models of flash memory
capacity_mb = (2 * 1024 / 1.08).round

root_pwd_crypt = '$1$XFCrfQHD$ZZoCa1Myqo1cGBMmPYOcH.'   # "centibel"

# check for root uid
raise 'must run as root' unless Process.uid == 0

# find pacman executable
if system('which pacman.static >/dev/null')
  pacman = 'pacman.static'
elsif system('which pacman >/dev/null')
  pacman = 'pacman'
else
  raise 'pacman not found in path -- maybe run prepare_host.rb?'
end

section 'creating empty image file (may take a while)'

system "dd if=/dev/zero of=#{filename} bs=1024k count=#{capacity_mb}"

section 'setting up filesystem'

# find free loopback device
lodevice = `losetup -f`.chomp

begin
  # set up loopback device
  system "losetup #{lodevice} #{filename}"

  # calculate number of "cylinders" assuming 255 heads, 63 sectors/track and 512 bytes/sector
  track_bytes = 255 * 63 * 512
  cylinders = capacity_mb * 2 ** 20 / track_bytes

  # create a Linux partition spanning the whole disk, beginnung at sector 63
  system "echo 63 | sfdisk --Linux -C #{cylinders} -uS #{lodevice}"

  # find free loopback device for the partition
  lopartition = `losetup -f`.chomp

  begin
    # set up loopback device for the partition
    # partition start is fixed (see above)
    # size derived from cylinder count minus start
    start_bytes = 63 * 512
    system "losetup --offset #{start_bytes} --sizelimit #{cylinders * track_bytes - start_bytes} #{lopartition} #{filename}"

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

          # save config files for later use in child process
          config_dir = "#{File.dirname $0}/../conf"

          lilo_config   = File.read "#{config_dir}/lilo.conf"
          rc_config     = File.read "#{config_dir}/rc.conf"

          # (copy player files)

          # create chrooted child
          #system "chroot #{target_dir}"
          fork do
            Dir.chroot target_dir

            section 'installing additional packages'

            system 'pacman -Sy --noconfirm lilo base-devel openssh cmake git smbclient qt mpd ruby ruby-mpd kdebindings-smoke bsd-games'

            # qtruby4 needs to be built (gem is outdated)

            # symlink is necessary for build to succeed (found on
            # <http://rubyforge.org/forum/forum.php?thread_id=42757&forum_id=723>)
            File.symlink '../i686-linux/ruby/config.h', '/usr/include/ruby-1.9.1/ruby/config.h'

            Dir.mkdir '/tmp/qtruby'
            Dir.chdir '/tmp/qtruby'
            system 'wget http://rubyforge.org/frs/download.php/53816/qt4-qtruby-2.0.3.tgz'
            system 'tar xzf qt4-qtruby-2.0.3.tgz'
            system 'cd qt4-qtruby-2.0.3 && cmake . && make && make install'
            # rm -rf /tmp/qtruby

            section 'configuring system'

            File.open('/etc/rc.conf', 'w')    { |f| f.write rc_config }
            File.open('/etc/lilo.conf', 'w')  { |f| f.write lilo_config }
            system 'lilo'

            File.open('/etc/fstab', 'a')      { |f| f.puts '/dev/sda1 / ext2 noatime 0 1' }

            File.open('/etc/locale.gen', 'a') do |f|
              f.puts 'en_GB.UTF-8 UTF-8'
              f.puts 'en_GB ISO-8859-1'
            end
            system 'locale-gen'

            system "usermod -p '#{root_pwd_crypt}' root"

            # everyone is blocked by default, but we want ssh to work
            File.unlink '/etc/hosts.deny'
          end

          # wait for child
          Process.wait
        ensure
          system "umount #{target_dir}/var/cache/pacman/pkg"
          system "umount #{target_dir}/sys"
          system "umount #{target_dir}/proc"
          system "umount #{target_dir}/dev"
        end
      ensure
        # unmount image
        #Dir.chdir '/'
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
