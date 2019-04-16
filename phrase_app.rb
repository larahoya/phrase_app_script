require 'nokogiri'
require 'pry'

def get_one_xml(path, language_code)
	# Find all strings XML files
	files_path =  path + language_code
	files = Dir["#{files_path}/strings_*.xml"]

	# Merge all XML files into one
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

def get_hash_from_localizable(file)
	hash = Hash.new
	text = File.foreach(file) { |line|
		unless line.valid_encoding?
			return
		end
		match = line.match("\\\"(.*?)\\\" = \\\"(.*?)\\\";\\n")
		unless match.nil?
			key, translation = match.captures
			hash[translation] = key
		end
	}
	return hash
end

def get_keys_hash(old_hash, new_hash)
	hash = Hash.new
	old_hash.each do |key, value|
		old_key = value
		new_key = new_hash[key]
		if new_key.nil?
			puts("NOT FOUND: #{key}")
		else
			hash[old_key] = new_key
		end
	end
	return hash
end

#Push android unique xml to phraseapp

#brew install phraseapp
#phraseapp init --> .phraseapp.yml

android_values_path = "../product_mobile_anqdroid_rider/rider/src/main/res/values-"
languages_codes = ["en", "es", "pt", "pt-BR"]
languages_codes.each { |language_code|
	xml = get_one_xml(android_values_path, language_code)
	save_xml(xml, "strings-#{language_code}.xml")
}
system("phraseapp push")

#Pull ios localizables
system("phraseapp pull")

#Get translation => key hash for new/old Localizables file
old_path = "./old/es.lproj/Localizable.strings"
new_path = "./new/es.lproj/Localizable.strings"

old_hash = get_hash_from_localizable(old_path)
new_hash = get_hash_from_localizable(new_path)

# Get old_key => new_key hash for Localizables
keys_hash = get_keys_hash(old_hash, new_hash)
