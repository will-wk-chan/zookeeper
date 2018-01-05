require 'mkmf'
require 'rbconfig'
require 'fileutils'

HERE = File.expand_path(File.dirname(__FILE__))
BUNDLE = Dir.glob("zkc-*.tar.gz").sort.last
ZKC_VERSION = BUNDLE[/(zkc-.*?)\.tar.gz$/, 1]
PATCHES = Dir.glob("patches/#{ZKC_VERSION}*.patch")

BUNDLE_PATH = File.join(HERE, ZKC_VERSION, 'c')

$EXTRA_CONF = ''

# CLANG!!!! jeez, if apple would only *stop* "thinking different"
if cc = RbConfig::CONFIG['CC'] && cc =~ /^gcc/
  $CC = cc
  $EXTRA_CONF = "#{$EXTRA_CONF} CC=#{$CC}"
end

$CFLAGS = "#{$CFLAGS}".gsub("$(cflags)", "").gsub("-arch ppc", "")
$LDFLAGS = "#{$LDFLAGS}".gsub("$(ldflags)", "").gsub("-arch ppc", "")
$CXXFLAGS = " -std=gnu++98 #{$CFLAGS}"
$CPPFLAGS = $ARCH_FLAG = ""

if RUBY_VERSION == '1.8.7'
  $CFLAGS << ' -DZKRB_RUBY_187'
end

ZK_DEBUG = (ENV['DEBUG'] or ARGV.any? { |arg| arg == '--debug' })
ZK_DEV = ENV['ZK_DEV']
DEBUG_CFLAGS = " -O0 -ggdb3 -DHAVE_DEBUG -fstack-protector-all"

if ZK_DEBUG
  $stderr.puts "*** Setting debug flags. ***"
  $EXTRA_CONF = "#{$EXTRA_CONF} --enable-debug"
  $CFLAGS.gsub!(/ -O[^0] /, ' ')
  $CFLAGS << DEBUG_CFLAGS
end

$includes = " -I#{HERE}/include"
$libraries = " -L#{HERE}/lib -L#{RbConfig::CONFIG['libdir']}"
$CFLAGS = "#{$includes} #{$libraries} #{$CFLAGS}"
$LDFLAGS = "#{$libraries} #{$LDFLAGS}"
$LIBPATH = ["#{HERE}/lib"]
$DEFLIBPATH = []

def safe_sh(cmd)
  puts cmd
  system(cmd)
  unless $?.exited? and $?.success?
    raise "command failed! #{cmd}"
  end
end

Dir.chdir(HERE) do
  if File.exist?("lib")
    puts "Zkc already built; run 'rake clobber' in ext/ first if you need to rebuild."
  else
    puts "Building zkc."

    unless File.exists?('c')
      safe_sh "tar xzf #{BUNDLE} 2>&1"
      PATCHES.each do |patch|
        safe_sh "patch -p0 < #{patch} 2>&1"
      end
    end

    # clean up stupid apple rsrc fork bullshit
    FileUtils.rm_f(Dir['**/._*'].select{|p| test(?f, p)})

    Dir.chdir(BUNDLE_PATH) do
      configure = "./configure --prefix=#{HERE} --with-pic --without-cppunit --disable-dependency-tracking #{$EXTRA_CONF} 2>&1"
      configure = "env CFLAGS='#{DEBUG_CFLAGS}' #{configure}" if ZK_DEBUG

      safe_sh(configure)
      safe_sh("make  2>&1")
      safe_sh("make install 2>&1")

      # for Windows/Cygwin add bin location to PATH
      isWindows = /cygwin/i === RbConfig::CONFIG['host_os']
      if isWindows
        # copy cygzookeepr*.dll to ruby/bin (must be a folder in $PATH)
        which_gem = `which gem` 
        ruby_bin_folder = File.dirname(which_gem)
        Dir.chdir("#{HERE}/bin") do
          %w[st mt].each do |stmt|
            %w[dll].each do |ext|
              # copy to ruby/bin
              safe_sh("cp cygzookeeper_#{stmt}-2.#{ext} #{ruby_bin_folder}")
            end
          end
        end
      end
    end

    system("rm -rf #{BUNDLE_PATH}") unless ZK_DEBUG or ZK_DEV
  end
end

win_dll_ext = ""
# For Windows/Cygwin, use *.dll.a libraries
is_windows = /cygwin/i === RbConfig::CONFIG['host_os']
if is_windows
  win_dll_ext = ".dll"
end

# Absolutely prevent the linker from picking up any other zookeeper_mt
Dir.chdir("#{HERE}/lib") do
  %w[st mt].each do |stmt|
    %w[a la].each do |ext|
      system("cp -f libzookeeper_#{stmt}#{win_dll_ext}.#{ext} libzookeeper_#{stmt}_gem#{win_dll_ext}.#{ext}")
    end
  end
end

# -lm must come after lzookeeper_st_gem to ensure proper link
$LIBS << " -lzookeeper_st_gem#{win_dll_ext} -lm"

have_func('rb_thread_blocking_region', 'ruby.h')
have_func('rb_thread_fd_select')

$CFLAGS << ' -Wall' if ZK_DEV
create_makefile 'zookeeper_c'

