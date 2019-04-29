require 'nokogiri'
require 'pry'
require 'json'

def get_xml_for_language(path, language_code)
	files_path = language_code.empty? ? path : path + "-" + language_code
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
		android_language_code = language_code[1]
		ios_language_code = language_code[0]
		xml = get_xml_for_language(path, android_language_code)
		save_xml(xml, "strings-#{ios_language_code}.xml")
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
		hash[remove_placeholders(node.text)] = key.value unless key.nil? || value.nil?
	}

	return hash
end

def get_hash_from_localizable(path, language_code)
	file_path = "#{path}/#{language_code}.lproj/Localizable.strings"
	hash = Hash.new
	text = File.foreach(file_path) { |line|
		return unless line.valid_encoding?
		match = line.match("\\\"(.*?)\\\" = \\\"(.*?)\\\";\\n")
		unless match.nil?
			key, translation = match.captures
			hash[remove_placeholders(translation)] = key
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

def remove_placeholders(text)
	placeholders = ['/\%\d\$s/', '/\%\d\$d/', '/\%s/', '/\%d/', '/\%@/']
	new_text = placeholders.reduce(text) { |result, regex|
		result.gsub(regex, '')
	}
	return new_text.gsub(/[áéíóú]/, '')
end

def get_snake_case_key(key)
	return key.gsub(/::/, '/')
    .gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2')
    .gsub(/([a-z\d])([A-Z])/,'\1_\2')
    .tr("-", "_")
    .downcase
    .gsub(' ', '_')
end

def replace_placeholders(translation)
	return if translation.nil?
	return translation.gsub("%@").with_index { |match, i|
		"%#{i + 1}$s"
	}
end

def add_missing_translations(ios_localizables_path, missing_keys, languages)
	languages.each do |ios_language_code, android_language_code|
		xml_file_path = "./strings-#{ios_language_code}.xml"
		xml_file = File.read(xml_file_path)
		xml = Nokogiri::XML(xml_file)
		ios_translations = get_hash_from_localizable(ios_localizables_path, ios_language_code)
		android_translations = get_hash_from_xml(xml_file_path)
		missing_keys.each do |key|
			translation = ios_translations.key(key)
			valid_android_key = get_snake_case_key(key)
			valid_android_translation = replace_placeholders(translation)
			already_exists = check_if_missing_key_already_exists(android_translations, valid_android_key)
			if already_exists
				node = "<string name=\"#{valid_android_key}_legacy\">#{valid_android_translation}</string>\n"
			else
				node = "<string name=\"#{valid_android_key}\">#{valid_android_translation}</string>\n"
			end
			xml.at('resources').add_child(node)
		end
		final_file_name = "final-strings-#{ios_language_code}.xml"
		save_xml(xml,final_file_name)
	end
end

def check_if_missing_key_already_exists(android_translations, missing_key)
	return android_translations.values.include? missing_key
end

def get_swift_gen_key(key)
	text = key.split('_').map.with_index { |word, index|
		index == 0 ? word[0].downcase + word[1..-1] : word.capitalize
	}.join
	return text.split(' ').map.with_index { |word, index|
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

def check_duplicated_keys(swift_gen_compared_keys)
	values = swift_gen_compared_keys.values
	return values.find_all { |e| values.count(e) > 1 }
end

def get_all_swift_files
	return Dir["../product_mobile_ios_rider/**/*.swift"]
end

def replace_keys(compared_keys, ios_folder_path)
	files = Dir[ios_folder_path]
	files.each do |file_path|
		text = File.read(file_path)
		new_contents = compared_keys.reduce(text) { |result, keys|
			result
			.gsub("L10n.#{keys[0]}\n", "L10n.#{keys[1]}\n")
			.gsub("L10n.#{keys[0]} ", "L10n.#{keys[1]} ")
			.gsub("L10n.#{keys[0]},", "L10n.#{keys[1]},")
			.gsub("L10n.#{keys[0]}(", "L10n.#{keys[1]}(")
			.gsub("L10n.#{keys[0]})", "L10n.#{keys[1]})")
		}
		File.open(file_path, "w") {|file| file.puts new_contents }
	end
end

android_resouces_path = "../product_mobile_android_rider/rider/src/main/res/values"
languages = {
	"es" => "es",
	"en" => "",
	"pt" => "pt",
	"pt-BR" => "pt-rBR",
}
ios_localizables_path = "../product_mobile_ios_rider/CabifyRider"
ios_folder_path = "../product_mobile_ios_rider/**/*.swift"

#### Phraseapp configuration
#brew install phraseapp
#phraseapp init --> .phraseapp.yml

#### Get unique XML from android files
get_xml(android_resouces_path, languages)

#### Get translation => key hash for android/ios translations
ios_old_translations = get_hash_from_localizable(ios_localizables_path, "es")
File.write("./ios_translations.json", JSON.pretty_generate(ios_old_translations))
android_translations = get_hash_from_xml("./strings-es.xml")

#### Get old_key => new_key hash for Localizables
compared_keys = get_compared_keys(ios_old_translations, android_translations)
missing_translations_keys = get_missing_translations_keys(ios_old_translations, android_translations)
File.write("./compared_keys.json", JSON.pretty_generate(compared_keys))
File.write("./missing_keys.json", JSON.pretty_generate(missing_translations_keys))

#### Include missing keys in XML before uploading to phraseapp
add_missing_translations(ios_localizables_path, missing_translations_keys, languages)
updated_android_translations = get_hash_from_xml("./final-strings-es.xml")

updated_compared_keys = get_compared_keys(ios_old_translations, updated_android_translations)
File.write("./final_compared_keys.json", JSON.pretty_generate(updated_compared_keys))

#### SwiftGen transformation
swift_gen_compared_keys = get_swift_gen_compared_keys(updated_compared_keys)
File.write("./swift_gen_compared_keys.json", JSON.pretty_generate(swift_gen_compared_keys))

duplicated_keys = check_duplicated_keys(swift_gen_compared_keys)
unless duplicated_keys.empty?
	raise "Duplicated keys: #{duplicated_keys}"
end

#### Push XML to phraseapp
# system("phraseapp push")

#### Pull iOS Localizables.strings
# system("phraseapp pull")

#### Replace old keys with new ones in ios project
replace_keys(swift_gen_compared_keys, ios_folder_path)
