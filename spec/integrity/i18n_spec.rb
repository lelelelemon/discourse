require "rails_helper"
require "i18n/duplicate_key_finder"

def extract_locale(path)
  path[/\.([^.]{2,})\.yml$/, 1]
end

PLURALIZATION_KEYS ||= ['zero', 'one', 'two', 'few', 'many', 'other']

def find_pluralizations(hash, parent_key = '', pluralizations = Hash.new)
  hash.each do |key, value|
    if Hash === value
      current_key = parent_key.blank? ? key : "#{parent_key}.#{key}"
      find_pluralizations(value, current_key, pluralizations)
    elsif PLURALIZATION_KEYS.include? key
      pluralizations[parent_key] = hash
    end
  end

  pluralizations
end

def flatten_hash(hash)
  hash.each_with_object({}) do |(k, v), h|
    if Hash === v
      flatten_hash(v).map do |h_k, h_v|
        h["#{k}.#{h_k}".freeze] = h_v
      end
    else
      h[k] = v
    end
  end
end

describe "i18n integrity checks" do

  it 'has an i18n key for each Trust Levels' do
    TrustLevel.all.each do |ts|
      expect(ts.name).not_to match(/translation missing/)
    end
  end

  it "has an i18n key for each Site Setting" do
    SiteSetting.all_settings.each do |s|
      next if s[/^test_/]
      expect(s[:description]).not_to match(/translation missing/)
    end
  end

  it "has an i18n key for each Badge description" do
    Badge.where(system: true).each do |b|
      expect(b.long_description).to be_present
      expect(b.description).to be_present
    end
  end

  Dir["#{Rails.root}/config/locales/client.*.yml"].each do |path|
    it "has valid client YAML for '#{path}'" do
      yaml = YAML.load_file(path)
      locale = extract_locale(path)

      expect(yaml.keys).to eq([locale])

      expect(yaml[locale]["js"]).to be
      expect(yaml[locale]["admin_js"]).to be
      # expect(yaml[locale]["wizard_js"]).to be
    end
  end

  Dir["#{Rails.root}/**/locale*/*.en.yml"].each do |english_path|
    english_document = Psych.parse_file(english_path)
    english_yaml = YAML.load_file(english_path)["en"]
    english_yaml_keys = flatten_hash(english_yaml).keys
    english_pluralizations = find_pluralizations(english_yaml)
    english_pluralized_keys = flatten_hash(english_pluralizations).keys
    english_unique_keys = (english_yaml_keys - english_pluralized_keys).to_set

    context(english_path) do
      it "has no duplicate keys" do
        english_duplicates = DuplicateKeyFinder.new.find_duplicates(english_document)
        expect(english_duplicates).to be_empty
      end

      english_pluralizations.each do |key, hash|
        next if key["messages.restrict_dependent_destroy"]

        it "has valid pluralizations for '#{key}'" do
          expect(hash.keys).to contain_exactly("one", "other")
        end
      end
    end

    Dir[english_path.sub(".en.yml", ".*.yml")].each do |path|
      next if path[".en.yml"]

      context(path) do
        locale = extract_locale(path)

        document = Psych.parse_file(path)
        yaml = YAML.load_file(path)

        it "has no duplicate keys" do
          duplicates = DuplicateKeyFinder.new.find_duplicates(document)
          expect(duplicates).to be_empty
        end

        it "does not overwrite another locale" do
          expect(yaml.keys).to eq([locale])
        end

        unless path["transliterate"]

          it "has exactly the same keys as the English file" do
            yaml_keys = flatten_hash(yaml[locale]).keys
            pluralized_keys = flatten_hash(find_pluralizations(yaml[locale])).keys
            unique_keys = (yaml_keys - pluralized_keys).to_set

            expect(unique_keys - english_unique_keys).to be_empty
          end

        end

      end

    end
  end

end
