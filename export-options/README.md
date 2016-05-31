# xcodebuild-export-options-generator

Generates plist file that configures archive exporting.

```
xcodebuild -exportArchive \
  -archivePath ARCHIVE_PATH \
  -exportPath EXPORT_PATH \
  -exportOptionsPlist EXPORT_OPTIONS
```

Generators available for:

* iOS (generate_ios_export_options.rb)
* OS X (generate_osx_export_options.rb)

# How to use?

* Create `export-options` folder and copy the `Gemfile` and a required generator to your repo
* Install `plist` gem with bundle: `BUNDLE_GEMFILE=export_options/Gemfile bundle install`
* Run the generator with bundle:  

```
BUNDLE_GEMFILE=export_options/Gemfile bundle exec ruby \  
  export_options/generate_ios_export_options.rb  
  -o EXPORT_OPTIONS_PATH  
  -a ARCHIVE_PATH  
```

OR:

```
BUNDLE_GEMFILE=export_options/Gemfile bundle exec ruby \  
  export_options/generate_osx_export_options.rb  
  -o EXPORT_OPTIONS_PATH  
  -a ARCHIVE_PATH
  -e EXPORT_METHID
```
