# 雲端打包時把桌面小工具（ios/App/Widget/）加進 Xcode 專案。
# 使用者沒有 Mac 不能用 Xcode 加 target，所以每次打包時用 xcodeproj 套件自動加；已經有就跳過。
require 'xcodeproj'

project = Xcodeproj::Project.open('ios/App/App.xcodeproj')
if project.targets.any? { |t| t.name == 'Widget' }
  puts '已經有 Widget target，跳過'
  exit 0
end
app = project.targets.find { |t| t.name == 'App' } or abort '找不到 App target'

widget = project.new_target(:app_extension, 'Widget', :ios, '17.0', nil, :swift)

group = project.main_group.new_group('Widget', 'Widget')
widget.add_file_references([group.new_reference('LedgerWidget.swift')])
group.new_reference('Info.plist')
group.new_reference('Widget.entitlements')

widget.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'io.github.robinrn0419.ledger.widget'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'Widget/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CODE_SIGN_ENTITLEMENTS'] = 'Widget/Widget.entitlements'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  s['SWIFT_VERSION'] = '5.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['SKIP_INSTALL'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

# App 編譯前先編小工具，編好放進 App.app/PlugIns/
app.add_dependency(widget)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(widget.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeaderOnCopy'] }

project.save
puts '已加入 Widget target'
