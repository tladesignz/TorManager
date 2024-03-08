#
# Be sure to run `pod lib lint TorManager.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'TorManager'
  s.version          = '0.1.0'
  s.summary          = 'The easiest way to integrate Tor and Pluggable Transports into your app.'

  s.description      = <<-DESC
This library bundles all building blocks to integrate Tor into your app:
- Tor.framework using
  - C-Tor
  - GeoIP files
- IPtProxyUI using
  - Lyrebird Pluggable Transport
  - Snowflake Pluggable Transport
  - Auto-configuration support via Moat/RdSys services
  - Auto-configuration support for IPv4/IPv6 cappable networks
- OrbotKit to detect and interact with a running Orbot
                       DESC

  s.homepage         = 'https://github.com/tladesignz/TorManager'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Benjamin Erhart' => 'berhart@netzarchitekten.com' }
  s.source           = { :git => 'https://github.com/tladesignz/TorManager.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/tladesignz'

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '11'

  # Needed because of the IPtProxy go-mobile library.
  s.static_framework = true

  s.source_files = 'TorManager/Classes/**/*'
  
  # s.resource_bundles = {
  #   'TorManager' => ['TorManager/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  s.dependency 'Tor/GeoIP', '~> 408.10'
  s.dependency 'IPtProxyUI', '~> 4.3'
  s.ios.dependency 'OrbotKit', '~> 1.1'

end
