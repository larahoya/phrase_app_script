require 'nokogiri'
require 'pry'
require 'json'

class PhraseApp

	@@android_resouces_path = "../product_mobile_android_rider/rider/src/main/res/values"
	## ios_language_code => android_language_code
	@@languages = {
		"es" => "es",
		"en" => "",
		"pt" => "pt",
		"pt-BR" => "pt-rBR",
	}
	@@ios_localizables_path = "../product_mobile_ios_rider/CabifyRider"
	@@ios_folder_path = "../product_mobile_ios_rider/**/*.swift"
	@@compared_keys_file_path = "./swift_gen_compared_keys.json"

	def self.replace_localizable_files
		#### Get unique XML from android files
		get_xml(@@android_resouces_path, @@languages)

		#### Get key => translation hash for android/ios translations
		ios_old_translations = get_hash_from_localizable(@@ios_localizables_path, "es")
		android_translations = get_hash_from_xml("./initial-strings-es.xml")
		File.write("./ios_translations.json", JSON.pretty_generate(ios_old_translations))

		#### Get old_key => new_key hash for Localizables
		missing_translations_keys = get_missing_translations_keys(ios_old_translations, android_translations)
		File.write("./missing_keys.json", JSON.pretty_generate(missing_translations_keys))

		#### Include missing keys in XML before uploading to phraseapp
		add_missing_translations(@@ios_localizables_path, missing_translations_keys, @@languages)
		updated_android_translations = get_hash_from_xml("./strings-es.xml")

		ios_translations_with_android_placeholders = replace_placeholder_from_hash(ios_old_translations)

		updated_compared_keys = get_compared_keys(ios_translations_with_android_placeholders, updated_android_translations)
		File.write("./compared_keys.json", JSON.pretty_generate(updated_compared_keys))

		#### SwiftGen transformation
		swift_gen_compared_keys = get_swift_gen_compared_keys(updated_compared_keys)
		File.write(@@compared_keys_file_path, JSON.pretty_generate(swift_gen_compared_keys))

		replace_android_placeholders(@@languages)

		#### Push XML to phraseapp
		system("phraseapp push")
		#### Pull iOS Localizables.strings
		system("phraseapp pull")
	end

	def self.swiftgenBuildPhase
		system('"../product_mobile_ios_rider/swiftgen-5.3.0/bin/swiftgen" strings "../product_mobile_ios_rider/CabifyRider/es.lproj/Localizable.strings" -t structured-swift3 --output "../product_mobile_ios_rider/CabifyRider/Constants/Strings.swift"')
	end

	def self.replace_strings_keys
		file = File.read @@compared_keys_file_path
		compared_keys = JSON.parse(file)
		replace_keys(compared_keys, @@ios_folder_path)
	end

	def self.get_xml_for_language(path, language_code)
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

	def self.save_xml(xml, filename)
		File.write(filename, xml.to_xml)
	end

	def self.get_xml(path, languages)
		languages.each { |language_code|
			android_language_code = language_code[1]
			ios_language_code = language_code[0]
			xml = get_xml_for_language(path, android_language_code)
			save_xml(xml, "initial-strings-#{ios_language_code}.xml")
		}
	end

	def self.get_hash_from_xml(filename)
		file = File.read(filename)
		xml = Nokogiri::XML(file)

		hash = Hash.new

		strings_nodes = xml.at('resources').children

		strings_nodes.each { |node|
			key = node.attributes['name']
			value = node.text
			hash[key.value] = node.text unless key.nil? || value.nil?
		}

		return hash
	end

	def self.get_hash_from_localizable(path, language_code)
		file_path = "#{path}/#{language_code}.lproj/Localizable.strings"
		hash = Hash.new
		text = File.foreach(file_path) { |line|
			return unless line.valid_encoding?
			match = line.match("\\\"(.*?)\\\" += +\\\"(.*?)\\\";\\n")
			unless match.nil?
				key, translation = match.captures
				hash[key] = translation
			end
		}
		return hash
	end

	def self.get_compared_keys(ios_translations, android_translations)
		shared_keys = Hash.new
		ios_translations.each do |ios_key, translation|
			android_key = android_translations.key(translation)
			shared_keys[ios_key] = android_key unless android_key.nil?
		end
		return shared_keys
	end

	def self.get_missing_translations_keys(ios_translations, android_translations)
		missing_translations = Array.new
		ios_translations.each do |ios_key, translation|
			android_key = android_translations.key(translation)
			missing_translations.push(ios_key) if android_key.nil?
		end
		return missing_translations
	end

	def self.get_snake_case_key(key, downcase)
		snake_case_key = key.gsub(/::/, '/')
	    .gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2')
	    .gsub(/([a-z\d])([A-Z])/,'\1_\2')
	    .tr("-", "_")
	    .gsub(' ', '_')

	    downcase ? snake_case_key.downcase : snake_case_key
	end

	def self.replace_placeholder_from_hash(hash)
		replaced_hash = Hash.new
		hash.each do |key, translation|
			replaced_hash[key] = replace_placeholders(translation)
		end
		return replaced_hash
	end

	def self.replace_placeholders(translation)
		return if translation.nil?
		return translation.gsub("%@").with_index { |match, i|
			"%#{i + 1}$s"
		}
	end

	def self.replace_android_placeholders(languages)
		languages.each do |ios_language_code, android_language_code|
			xml = Nokogiri::XML("<resources></resources>")
			android_translations = get_hash_from_xml("./strings-#{ios_language_code}.xml")
			android_translations.each do |key, translation|
				replaced_translation = replace_android_placeholder(translation)
				node = "<string name=\"#{key}\">#{replaced_translation}</string>\n"
				xml.at('resources').add_child(node)
			end
			save_xml(xml,"replaced-strings-#{ios_language_code}.xml")
		end
	end

	def self.replace_android_placeholder(translation)
		translation.gsub("%1s", "%1$s")
	end

	def self.add_missing_translations(ios_localizables_path, missing_keys, languages)
		languages.each do |ios_language_code, android_language_code|
			xml_file_path = "./initial-strings-#{ios_language_code}.xml"
			xml_file = File.read(xml_file_path)
			xml = Nokogiri::XML(xml_file)
			ios_translations = get_hash_from_localizable(ios_localizables_path, ios_language_code)
			android_translations = get_hash_from_xml(xml_file_path)
			missing_keys.each do |key|
				translation = ios_translations[key]
				valid_android_key = get_snake_case_key(key, true)
				valid_android_translation = replace_placeholders(translation)
				already_exists = check_if_missing_key_already_exists(android_translations, valid_android_key)
				final_key = already_exists ? valid_android_key + "_legacy" : valid_android_key
				node = "<string name=\"#{final_key}\">#{valid_android_translation}</string>\n"
				xml.at('resources').add_child(node)
			end
			final_file_name = "strings-#{ios_language_code}.xml"
			save_xml(xml,final_file_name)
		end
	end

	def self.check_if_missing_key_already_exists(android_translations, missing_key)
		return android_translations.keys.include? missing_key
	end

	def self.get_swiftgen_key(key, downcase)
		get_snake_case_key(key, downcase)
		.split('_').map.with_index { |word, index|
			if word.upcase == word && downcase == false
				index == 0 ? word.downcase : word
			else
				index == 0 ? word[0].downcase + word[1..-1] : word.capitalize
			end
		}
		.join
	end

	def self.get_swift_gen_compared_keys(updated_compared_keys)
		result = Hash.new
		updated_compared_keys.each do |old_key, new_key|
			result[get_swiftgen_key(old_key, false)] = get_swiftgen_key(new_key, true)
		end
		return result
	end

	def self.check_duplicated_keys(swift_gen_compared_keys)
		values = swift_gen_compared_keys.values
		return values.find_all { |e| values.count(e) > 1 }
	end

	def self.get_all_swift_files
		return Dir["../product_mobile_ios_rider/**/*.swift"]
	end

	def self.replace_keys(compared_keys, ios_folder_path)
		files = Dir[ios_folder_path]
		files.each do |file_path|
			text = File.read(file_path)
			new_contents = compared_keys.reduce(text) { |result, keys|
				["\n", " ", ",", "(", ")", "]", "."].reduce(result) { |result, character|
					result.gsub("L10n.#{keys[0]}#{character}", "L10n.#{keys[1]}#{character}")
				}
			}
			File.open(file_path, "w") {|file| file.puts new_contents }
		end
	end

end

#### Phraseapp configuration
#brew install phraseapp
#phraseapp init --> .phraseapp.yml

PhraseApp.replace_localizable_files
PhraseApp.swiftgenBuildPhase
PhraseApp.replace_strings_keys
