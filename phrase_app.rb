require 'nokogiri'
require 'pry'

def get_xml_for_language(path, language_code)
	files_path =  path + language_code
	files = Dir["#{files_path}/strings_*.xml"]

	xml = Nokogiri::XML("<resources></resources>")

	files.each { |path|
		content = File.read(path)
		resources = Nokogiri::XML(content).search('resources').children
		xml.at('resources').add_child(resources)	
	}

	return xml
end

def save_xml(xml, filename)
	File.write(filename, xml.to_xml)
end

def get_xml(path, languages)
	languages.each { |language_code|
		xml = get_xml_for_language(path, language_code)
		save_xml(xml, "strings-#{language_code}.xml")
	}
end

def get_hash_from_xml(filename)
	file = File.read(filename)
	xml = Nokogiri::XML(file)

	hash = Hash.new

	strings_nodes = xml.at('resources').children

	strings_nodes.each { |node|
		key = node.attributes['name']
		value = node.text
		hash[node.text] = key.value unless key.nil? || value.nil?
	}

	return hash
end

def get_hash_from_localizable(file)
	hash = Hash.new
	text = File.foreach(file) { |line|
		return unless line.valid_encoding?
		match = line.match("\\\"(.*?)\\\" = \\\"(.*?)\\\";\\n")
		unless match.nil?
			key, translation = match.captures
			fixed_translation = get_new_parametrized_translation(translation)
			hash[fixed_translation] = key
		end
	}
	return hash
end

def get_compared_keys(ios_translations, android_translations)
	shared_keys = Hash.new
	ios_translations.each do |translation, ios_key|
		android_key = android_translations[translation]
		unless android_key.nil?
			shared_keys[ios_key] = android_key
		end
	end
	return shared_keys
end

def get_missing_translations_keys(ios_translations, android_translations)
	missing_translations = Array.new
	ios_translations.each do |translation, ios_key|
		android_key = android_translations[translation]
		if android_key.nil?
			missing_translations.push(ios_key)
		end
	end
	return missing_translations
end

def get_new_parametrized_translation(text)
	return text.gsub("%@").with_index { |match, i|
		"%#{i + 1}$s"
	}
end

def get_snake_case_key(key)
	return key.gsub(/::/, '/')
    .gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2')
    .gsub(/([a-z\d])([A-Z])/,'\1_\2')
    .tr("-", "_")
    .downcase
end

def add_missing_translations(missing_keys, languages)
	languages.each do |language_code|
		xml_file = File.read("./strings-#{language_code}.xml")
		xml = Nokogiri::XML(xml_file)
		translations = get_hash_from_localizable("./old/#{language_code}.lproj/Localizable.strings")
		missing_keys.each do |key|
			translation = translations.key(key)
			name = get_snake_case_key(key)
			node = "<string name=\"#{name}\">#{translation}</string>\n"
			xml.at('resources').add_child(node)
		end
		save_xml(xml,"strings-#{language_code}.xml" )
	end
end

def get_swift_gen_key(key)
	return key.split('_').map.with_index { |word, index|
		index == 0 ? word[0].downcase + word[1..-1] : word.capitalize
	}.join
end

def get_swift_gen_compared_keys(updated_compared_keys)
	result = Hash.new
	updated_compared_keys.each do |old_key, new_key|
		result[get_swift_gen_key(old_key)] = get_swift_gen_key(new_key)
	end
	return result
end

def get_all_swift_files
	return Dir["../product_mobile_ios_rider/**/*.swift"]
end

def replace_keys(compared_keys, ios_folder_path)
	files = Dir[ios_folder_path]
	files.each do |file_path|
		text = File.read(file_path)
		new_contents = compared_keys.reduce(text) { |result, keys|
			result.gsub("L10n.#{keys[0]}", "L10n.#{keys[1]}")
		}
		File.open(file_path, "w") {|file| file.puts new_contents }
	end
end

android_resouces_path = "../product_mobile_android_rider/rider/src/main/res/values-"
languages = ["es"]
ios_localizable_path = "./old/es.lproj/Localizable.strings"
ios_folder_path = "../product_mobile_ios_rider/**/*.swift"
new_xml_path = "./strings-es.xml"

#### Phraseapp configuration
#brew install phraseapp
#phraseapp init --> .phraseapp.yml

#### Get unique XML from android files
get_xml(android_resouces_path, languages)

#### Get translation => key hash for android/ios translations
ios_old_translations = get_hash_from_localizable(ios_localizable_path)
android_translations = get_hash_from_xml(new_xml_path)

#### Get old_key => new_key hash for Localizables
compared_keys = get_compared_keys(ios_old_translations, android_translations)
missing_translations_keys = get_missing_translations_keys(ios_old_translations, android_translations)

#### Include missing keys in XML before uploading to phraseapp
add_missing_translations(missing_translations_keys, languages)
updated_android_translations = get_hash_from_xml(new_xml_path)

updated_compared_keys = get_compared_keys(ios_old_translations, updated_android_translations)

#### SwiftGen transformation
swift_gen_compared_keys = get_swift_gen_compared_keys(updated_compared_keys)

#### Push XML to phraseapp
system("phraseapp push")

#### Pull iOS Localizables.strings
system("phraseapp pull")

#### Replace old keys with new ones in ios project
replace_keys(swift_gen_compared_keys, ios_folder_path)
