Pod::Spec.new do |s|
  s.name             = 'sipkit_flutter'
  s.version          = '0.1.0'
  s.summary          = 'SipKit Flutter SDK — token-licensed SIP/VoIP SDK for Flutter.'
  s.description      = <<-DESC
    SipKit provides voice + video calling for Flutter apps, gated by an
    entitlement JWT from the SipKit licensing backend.  Includes WebrtcEngine
    (sip_ua + flutter_webrtc) and PjsipEngine (PJSUA2 + CallKit on iOS).
  DESC
  s.homepage         = 'https://github.com/sipkit/sipkit_flutter'
  s.license          = { :type => 'GPL-2.0-or-later' }
  s.author           = { 'SipKit' => 'hello@sipkit.io' }
  s.source           = { :path => '.' }
  pjsip_xcframework = 'Frameworks/PJSIP.xcframework'
  s.source_files = ['Classes/**/*.swift', 'Classes/PJSIPBridge.h']
  if File.exist?(pjsip_xcframework)
    s.source_files += ['Classes/PJSIPBridge.mm']
    s.vendored_frameworks = pjsip_xcframework
  else
    s.source_files += ['Classes/PJSIPUnavailableBridge.m']
  end
  s.dependency 'Flutter'
  s.platform     = :ios, '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
  s.frameworks = 'CallKit', 'AVFoundation', 'PushKit'
end
