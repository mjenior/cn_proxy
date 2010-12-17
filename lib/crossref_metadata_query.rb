require 'rubygems'
require 'open-uri'

class CrossRefError < StandardError
  attr_accessor :status
  def initialize(message, status)
    @status = status
    super(message)   
  end
end

class CrossrefMetadataQuery

  attr_reader :unixref

  def initialize doi 
    get_unixref doi  
  end

  private

  def get_unixref doi
    @unixref = open("http://www.crossref.org/openurl/?id=#{doi}&noredirect=true&pid=gbilder@crossref.org&format=unixref").read
    scrape_for_errors    
  end

  def scrape_for_errors 
    case @unixref
    when /\<journal\>/, /\<conference\>/
      return
    when  /Unable to parse or validate the xml query/
      #raise "400 Invalid DOI"
      raise CrossRefError.new("Invalid DOI", "400")
    when /Malformed DOI/
      #raise "400 Invalid DOI"
      raise CrossRefError.new("Invalid DOI", "400")
    when  /not found in CrossRef/
      #raise "404 DOI not found"
      raise CrossRefError.new("DOI not found. Are you sure it is a CrossRef DOI?", "404")
    when /The login you supplied is not recognized/
      #raise "403 Authentication failed"
      raise CrossRefError.new("Authentication failed.", "403")
    else
      raise "501 Internal Error"
    end
  end
end
