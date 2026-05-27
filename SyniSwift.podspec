Pod::Spec.new do |s|
  s.name             = 'SyniSwift'
  s.version          = '0.0.3'
  s.summary          = 'Swift SDK for the Synheart on-device LLM agent runtime.'
  s.description      = <<-DESC
Swift SDK for Syni — adaptive on-device LLM inference with hybrid
local / cloud chat, structured persona conditioning, and a streaming
chat API for iOS / macOS. Thin Swift wrapper around the syni-runtime
native core plus the Synheart cloud agent API.
                       DESC
  s.homepage         = 'https://github.com/synheart-ai/syni-swift'
  s.license          = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author           = { 'SynHeart AI' => 'eng@synheart.ai' }
  s.source           = { :git => 'https://github.com/synheart-ai/syni-swift.git', :tag => "v#{s.version}" }

  s.source_files     = 'Sources/SyniSwift/**/*.swift'
  s.swift_version    = '5.9'
  s.ios.deployment_target  = '16.0'
  s.osx.deployment_target  = '13.0'

  # Native runtime is shipped by the `synheart` CLI, not by this pod.
  # Run `synheart install runtime syni` once in your project; it writes
  # `SyniRuntime.xcframework` to `<app>/synheart/vendor/syni-runtime/`.
  # Add that framework to your Xcode target under General →
  # Frameworks, Libraries, and Embedded Content. SyniRuntimeBridge
  # resolves all C symbols at runtime via `dlsym(RTLD_DEFAULT)`, so the
  # pod compiles standalone; calls fail with a clear error until the
  # XCFramework is wired in.

  s.user_target_xcconfig = {
    # Preserve syni_* globals through Archive's strip so dlsym can
    # still resolve them in TestFlight / Release builds.
    'STRIP_STYLE' => 'non-global',
  }
end
