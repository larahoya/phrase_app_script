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

def get_shared_keys(ios_translations, android_translations)
	shared_keys = Hash.new
	ios_translations.each do |translation, ios_key|
		android_key = android_translations[translation]
		unless android_key.nil?
			shared_keys[ios_key] = android_key
		end
	end
	return shared_keys
end

def get_missing_keys(ios_translations, android_translations)
	missing_keys = Array.new
	ios_translations.each do |translation, ios_key|
		android_key = android_translations[translation]
		if android_key.nil?
			missing_keys.push(ios_key)
		end
	end
	return missing_keys
end

def get_new_parametrized_translation(text)
	return text.gsub("%@").with_index { |match, i|
		"%#{i + 1}$s"
	}
end

android_resouces_path = "../product_mobile_android_rider/rider/src/main/res/values-"
languages = ["en", "es", "pt", "pt-BR"]
ios_localizable_path = "./old/es.lproj/Localizable.strings"
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
shared_keys = get_shared_keys(ios_old_translations, android_translations)
missing_keys = get_missing_keys(ios_old_translations, android_translations)

#### Include missing keys in XML before uploading to phraseapp

#### SwiftGen transformation

#### Push XML to phraseapp
system("phraseapp push")

#### Pull iOS Localizables.strings
system("phraseapp pull")

#### Replace old keys with new ones in ios project
