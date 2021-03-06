require "json"
require "uri"
require 'unidecode'

require_relative "errors"

class CiteProcHelper

  @@styles = {}
  @@locales = {}

  def initialize record, settings
    @record = record
    @settings = settings
  end

  def issued
    date_parts = []
    date_parts << @record.publication_year if @record.publication_year
    date_parts << @record.publication_month if @record.publication_month
    date_parts << @record.publication_day if @record.publication_day

    {:"date-parts" => [date_parts]}
  end

  def page
    if @record.first_page && @record.last_page
      @record.first_page + "-" + @record.last_page
    elsif @record.first_page
      @record.first_page
    else
      nil
    end
  end

  def as_json
    as_data.to_json
  end

  def to_name_map contributor
    hsh = {:family => contributor.surname}
    hsh[:given] = contributor.given_name if contributor.given_name
    hsh
  end

  def as_data
    data = {
      :volume => @record.volume,
      :issue => @record.issue,
      :number => @record.edition_number,
      :DOI => @record.doi,
      :URL => "http://dx.doi.org/" + @record.doi,
      :ISBN => @record.isbn,
      :title => @record.title,
      :'container-title' => @record.publication_title,
      :publisher => @record.publisher_name,
      :issued => issued,
      :author => @record.authors.map {|c| to_name_map(c)},
      :editor => @record.editors.map {|c| to_name_map(c)},
      :page => page
    }

    data[:type] = case @record.publication_type
                  when :journal then "article-journal"
                  when :conference then "paper-conference"
                  when :report then "report"
                  when :dissertation then "thesis"
                  when :book then "book"
                  else
                    "misc"
                  end

    data.each_pair do |k,v|
      if v.nil?
        # Remove items that aren't present in the CrossRef record.
        data.delete k
      end
    end

    data
  end

 def load_locale locale
    raise UnknownLocale.new if @settings.locales[locale].nil?
    if @@locales[locale].nil?
      File.open(@settings.locales[locale], "r") do |file|
        @@locales[locale] = Nokogiri::XML.parse(file)
      end
    end
    @@locales[locale]
  end

  def load_style style
    raise UnknownStyle.new if @settings.styles[style].nil?
    if @@styles[style].nil?
      File.open(@settings.styles[style], "r") do |file|
        @@styles[style] = Nokogiri::XML.parse(file)
      end
    end
    @@styles[style]
  end

  def as_style opts={}
    options = {
      :format => "text",
      :style => "bibtex",
      :locale => "en-US"
    }.merge(opts)

    raise UnknownFormat unless ["text", "rtf", "html"].include?(options[:format])

    style_data = load_style options[:style]
    locale_data = load_locale options[:locale]
    bib_data = as_data
    bib_data["id"] = "item"

    source = open(@settings.xmle4xjs, "r:UTF-8").read + "\n" + open(@settings.citeprocjs, "r:UTF-8").read
    source += "\n" + <<-JS
      var style = #{style_data.to_json};
      var locale = #{locale_data.to_json};
      var item = #{bib_data.to_json};
      var sys = {};
      sys.retrieveItem = function(id) { return item };
      sys.retrieveLocale = function(id) { return locale };
      var citeProc = new CSL.Engine(sys, style);
      citeProc.updateItems(["item"]);
      citeProc.setOutputFormat("#{options[:format]}");
      var bib = citeProc.makeBibliography();
      var result = "Not enough metadata to construct bibliographic item.";
      if (bib[0]["bibliography_errors"].length == 0) {
        result = bib[1][0];
      }
      print(result);
    JS

    result = ""

    Tempfile.open("js") do |file|
      file.write source
      file.close
      IO.popen("js -f #{file.path}") do |p|
        result = p.read
      end
      file.unlink
    end

    if options[:style] == 'bibtex'
      fix_bibtex_key(result.strip)
    else
      result.strip
    end
  end

  # CSL can make a mess of bibtex keys, leaving spaces in the key if an author's
  # surname has spaces, thus creating invalid bibtex.
  # We also shorten very long bibtex keys, which CSL sometimes creates.
  def fix_bibtex_key bibtex
    key = bibtex.match(/\A@\w*{([^,]+),/)[1]
    key = key.gsub(' ', '_').gsub('.', '_')
    key = key[-30..-1] if key.length > 30
    key = key.to_ascii
    key = key.sub(/\A_+/, '')

    bibtex.sub(/{([^,]+),/, "{#{key},")
  end

end
