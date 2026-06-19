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
  s.license          = { :type => 'Proprietary', :text => 'Contact SipKit for licensing terms.' }
  s.author           = { 'SipKit' => 'hello@sipkit.io' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  # Uncomment when PJSIP prebuilt xcframework is available:
  # s.dependency 'pjsip', '~> 2.14'

  s.platform     = :ios, '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
  s.frameworks = 'CallKit', 'AVFoundation', 'PushKit'
end
