#!/usr/bin/env ruby

# centiBel : media player
#
# Disk image to OVA converter
#
# == Synopsis 
#   Convert raw disk image to ovf (Open Virtualization Format).
#   Requires VBoxManage (included in universe/virtualbox-ose on Ubuntu).
#
#   designed with the Open Virtualization Format Specification in mind:
#   <http://www.dmtf.org/standards/published_documents/DSP0243_1.0.0.pdf>
#
# == Usage 
#   img2ova.rb [options] imagefile
#
#   For help, use: img2ova.rb -h
#
# == Options
#   -o, --output FILENAME            Set target image filename
#                                    (default based on image filename)
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

require 'digest/sha1'
require 'optparse'
require 'rdoc/usage'
require 'readline'
require 'term/ansicolor'
require 'tmpdir'

include Term::ANSIColor

##### helper subroutines #####

def section title
  puts '', bold(black("*** #{title} ***")), ''
end

def continue?
  puts
  begin
    line = Readline.readline cyan('continue (y/[n])? ')
  end until ['y', 'n', ''].any? { |w| w == line }

  exit 2 unless line == 'y'
end

def descriptor_xml(args)
  image_filename  = args[:image_filename] || raise('no image filename given')
  image_filesize  = args[:image_filesize] || raise('no image filesize given')
  vdisk_size      = args[:vdisk_size]     || raise('no vdisk size given')
  DATA.read.
    sub(/%image_filename%/, image_filename).
    sub(/%image_filesize%/, image_filesize.to_s).
    sub(/%vdisk_size%/, vdisk_size.to_s)
end

##### main program #####

# set defaults

options = {}

# parse command line

OptionParser.new do |opts|
  opts.version = "0.4.0"
  opts.release = "2010-02-26"

  opts.banner = "Usage: img2ova.rb [options] imagefile"

  opts.separator ""
  opts.separator "Specific options:"

  opts.on("-o", "--output FILENAME", "Set target image filename (default based on image filename)") do |b|
    options[:output_filename] = b
  end
  opts.on("--manual", "Display manual") do
    puts opts.ver
    RDoc::usage
  end
end.parse!

puts white + bold + 'centiBel : media player -- image to ova conversion' + reset

imagefile = ARGV[0]
unless imagefile
  raise 'no image filename given'
end

basename = imagefile.sub /\.img$/i, ''
outputfile = options[:output_filename] || "#{basename}.ova"

if File.exists? outputfile
  puts "WARNING: output file \"#{outputfile}\" will be overwritten"
  continue?
end

Dir.mktmpdir do |target_dir|
  current_dir = Dir.pwd
  Dir.chdir target_dir

  section 'converting disk image'

  system "VBoxManage convertfromraw -format VMDK #{current_dir}/#{imagefile} #{basename}.vmdk"

  section 'creating metadata'

  ovf_file_data = descriptor_xml(
      :image_filename => "#{basename}.vmdk",
      :image_filesize => File.size("#{basename}.vmdk"),
      :vdisk_size => File.size("#{current_dir}/#{imagefile}"))

  File.open("#{basename}.ovf", 'w') { |f| f.write ovf_file_data }

  puts 'calculating checksums...'

  File.open("#{basename}.mf", 'w') do |f|
    f.puts "SHA1 (#{basename}.ovf)= #{Digest::SHA1.hexdigest(ovf_file_data)}"
    f.puts "SHA1 (#{basename}.vmdk)= #{Digest::SHA1.file("#{basename}.vmdk").hexdigest}"
  end

  section 'creating tar package'

  system "tar --format=ustar -cf #{current_dir}/#{outputfile} #{basename}.ovf #{basename}.mf #{basename}.vmdk"

end

section 'done'

# OVF descriptor template below, based on VirtualBox export

__END__
<?xml version="1.0"?>
<Envelope ovf:version="1.0" xml:lang="en-US"
    xmlns="http://schemas.dmtf.org/ovf/envelope/1"
    xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1"
    xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData"
    xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <References>
    <File ovf:href="%image_filename%" ovf:id="file1" ovf:size="%image_filesize%"/>
  </References>
  <DiskSection>
    <Info>List of the virtual disks used in the package</Info>
    <Disk ovf:capacity="%vdisk_size%" ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:format="http://www.vmware.com/specifications/vmdk.html#sparse"/>
  </DiskSection>
  <NetworkSection>
    <Info>Logical networks used in the package</Info>
    <Network ovf:name="NAT">
      <Description>Logical network used by this appliance.</Description>
    </Network>
  </NetworkSection>
  <VirtualSystem ovf:id="centiBel">
    <Info>A virtual machine</Info>
    <ProductSection>
      <Info>Meta-information about the installed software</Info>
      <Product>media player</Product>
      <!-- <Version>0.0.1</Version> -->
      <ProductUrl>http://www.centibel.org/</ProductUrl>
    </ProductSection>
    <OperatingSystemSection ovf:id="99">
      <Info>The kind of installed guest operating system</Info>
      <Description>Linux26</Description>
    </OperatingSystemSection>
    <VirtualHardwareSection>
      <Info>Virtual hardware requirements for a virtual machine</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemIdentifier>centiBel</vssd:VirtualSystemIdentifier>
        <vssd:VirtualSystemType>virtualbox-2.2</vssd:VirtualSystemType>
      </System>
      <Item>
        <rasd:Caption>1 virtual CPU</rasd:Caption>
        <rasd:ElementName>1 virtual CPU</rasd:ElementName>
        <rasd:Description>Number of virtual CPUs</rasd:Description>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>1</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:Caption>256 MB of memory</rasd:Caption>
        <rasd:ElementName>256 MB of memory</rasd:ElementName>
        <rasd:Description>Memory Size</rasd:Description>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:AllocationUnits>MegaBytes</rasd:AllocationUnits>
        <rasd:VirtualQuantity>256</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:Caption>ideController0</rasd:Caption>
        <rasd:ElementName>ideController0</rasd:ElementName>
        <rasd:Description>IDE Controller</rasd:Description>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceType>5</rasd:ResourceType>
        <rasd:ResourceSubType>PIIX4</rasd:ResourceSubType>
        <rasd:Address>1</rasd:Address>
      </Item>
      <Item>
        <rasd:Caption>floppy0</rasd:Caption>
        <rasd:ElementName>floppy0</rasd:ElementName>
        <rasd:Description>Floppy Drive</rasd:Description>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:ResourceType>14</rasd:ResourceType>
        <rasd:AutomaticAllocation>false</rasd:AutomaticAllocation>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
      </Item>
      <Item>
        <rasd:Caption>Ethernet adapter on 'NAT'</rasd:Caption>
        <rasd:ElementName>Ethernet adapter on 'NAT'</rasd:ElementName>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:ResourceType>10</rasd:ResourceType>
        <rasd:ResourceSubType>PCNet32</rasd:ResourceSubType>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Connection>NAT</rasd:Connection>
      </Item>
      <Item>
        <rasd:Caption>usb</rasd:Caption>
        <rasd:ElementName>usb</rasd:ElementName>
        <rasd:Description>USB Controller</rasd:Description>
        <rasd:InstanceID>6</rasd:InstanceID>
        <rasd:ResourceType>23</rasd:ResourceType>
        <rasd:Address>0</rasd:Address>
      </Item>
      <Item>
        <rasd:Caption>sound</rasd:Caption>
        <rasd:ElementName>sound</rasd:ElementName>
        <rasd:Description>Sound Card</rasd:Description>
        <rasd:InstanceID>7</rasd:InstanceID>
        <rasd:ResourceType>35</rasd:ResourceType>
        <rasd:ResourceSubType>ensoniq1371</rasd:ResourceSubType>
        <rasd:AutomaticAllocation>false</rasd:AutomaticAllocation>
        <rasd:AddressOnParent>3</rasd:AddressOnParent>
      </Item>
      <Item>
        <rasd:Caption>disk1</rasd:Caption>
        <rasd:ElementName>disk1</rasd:ElementName>
        <rasd:Description>Disk Image</rasd:Description>
        <rasd:InstanceID>8</rasd:InstanceID>
        <rasd:ResourceType>17</rasd:ResourceType>
        <rasd:HostResource>/disk/vmdisk1</rasd:HostResource>
        <rasd:Parent>3</rasd:Parent>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
      </Item>
      <Item>
        <rasd:Caption>cdrom1</rasd:Caption>
        <rasd:ElementName>cdrom1</rasd:ElementName>
        <rasd:Description>CD-ROM Drive</rasd:Description>
        <rasd:InstanceID>9</rasd:InstanceID>
        <rasd:ResourceType>15</rasd:ResourceType>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Parent>3</rasd:Parent>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
      </Item>
    </VirtualHardwareSection>
  </VirtualSystem>
</Envelope>
