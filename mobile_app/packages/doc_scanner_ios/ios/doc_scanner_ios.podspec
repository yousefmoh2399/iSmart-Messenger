Pod::Spec.new do |s|
  s.name             = 'doc_scanner_ios'
  s.version          = '0.0.1'
  s.summary          = 'iOS native document scanner plugin for iSmart Messenger'
  s.description      = <<-DESC
Native document scanner using AVFoundation, Vision, and CoreImage.
                       DESC
  s.homepage         = 'https://github.com/yousefmoh2399/iSmart-Messenger'
  s.license          = { :type => 'BSD' }
  s.author           = { 'iSmart' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'

  s.frameworks       = 'AVFoundation', 'Vision', 'CoreImage', 'CoreMedia', 'ImageIO', 'UIKit', 'Metal'
end
