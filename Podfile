platform :osx, '26.0'
use_frameworks!

target 'Clipy' do

  # Application
  pod 'PINCache'
  pod 'Sauce'
  pod 'Sparkle', '~> 2.6'
  pod 'RealmSwift', '~> 10.54'
  pod 'RxCocoa', '~> 6.7'
  pod 'RxSwift', '~> 6.7'
  pod 'LoginServiceKit'
  pod 'KeyHolder'
  pod 'Magnet'
  pod 'RxScreeen', '~> 2.2'
  pod 'LetsMove'
  pod 'SwiftHEXColors'
  # Utility
  pod 'BartyCrouch'
  pod 'SwiftLint', '~> 0.65.1'
  pod 'SwiftGen'

  target 'ClipyTests' do
    inherit! :search_paths

    pod 'Quick', '~> 7.6'
    pod 'Nimble', '~> 13.7'
  
  end

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '26.0'
    end
  end
end
