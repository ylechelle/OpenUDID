Pod::Spec.new do |s|
  s.name         = 'OpenUDID'
  s.version      = '1.0.1'
  s.summary      = 'OpenUDID.'
  s.homepage     = 'https://github.com/magnusguo/OpenUDID'
  s.license      = { :type => 'Apache', :file => 'LICENSE' }
  s.source       = { :git => 'https://github.com/magnusguo/OpenUDID.git', :tag => "#{s.version}" }
  s.author       = { 'Magnus' => 'https://github.com/magnusguo' }
  s.ios.deployment_target = '6.0'
  s.source_files = 'OpenUDID/*.{h,m}'
  s.requires_arc = true
end
