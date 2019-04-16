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

def get_hash(xml)
	hash = Hash.new

	strings_nodes = xml.at('resources').children

	strings_nodes.each { |node|
		key = node.attributes['name']
		value = node.text
		unless key.nil? || value.nil?
			hash[key.value] = node.text
		end
	}

	return hash
end

#Push android unique xml to phraseapp

#brew install phraseapp
#phraseapp init --> .phraseapp.yml

android_values_path = "../product_mobile_android_rider/rider/src/main/res/values-"
languages_codes = ["en", "es", "pt", "pt-BR"]
languages_codes.each { |language_code|
	xml = get_one_xml(android_values_path, language_code)
	save_xml(xml, "strings-#{language_code}.xml")
}
system("phraseapp push")

#Pull ios localizables
system("phraseapp pull")
