class GeocoderController < ApplicationController
  require 'uri'
  require 'net/http'
  require 'rexml/document'

  before_filter :authorize_web
  before_filter :set_locale

  def search
    @query = params[:query]
    qterms = @query.split(',')
    act = qterms.at(0)
    if act.nil? then # empty string, let osm handle
      osm_search
    else
     w = Word.find_by_lemma(act.downcase)
     if w.nil? then # the word is not an activity, do standard search
        osm_search
     else
       wsyns = w.synonyms.map{|x| OntologyClass.find_by_name(x.lemma.capitalize)}
       wsyns.delete(nil)
      if wsyns == [] then # no class found, do standard search
        osm_search
      else
        #interval search here
        interv = qterms.at(1)
        @interval = Interval.new(:start => 0, :stop => 0)
        if not interv.nil? then
          # we have a term that might be an interval
          intlist = Interval.parse_one(interv)
          if intlist != [] then
            # we have some intervals, we need to set up parameters
            @interval = intlist.first.first
            qterms.delete_at(1)
          end
        end
        @classes = wsyns.uniq.map{|x| x.id.to_s}
        qterms.delete_at(0)
        @query = qterms.to_s
        osm_search
      end
     end
    end

    #osm_search
  end

  def osm_search
    @sources = Array.new

    @query.sub(/^\s+/, "")
    @query.sub(/\s+$/, "")

    if @query.match(/^[+-]?\d+(\.\d*)?\s*[\s,]\s*[+-]?\d+(\.\d*)?$/)
      @sources.push "latlon"
    elsif @query.match(/^\d{5}(-\d{4})?$/)
      @sources.push "us_postcode"
      @sources.push "osm_nominatim"
    elsif @query.match(/^(GIR 0AA|[A-PR-UWYZ]([0-9]{1,2}|([A-HK-Y][0-9]|[A-HK-Y][0-9]([0-9]|[ABEHMNPRV-Y]))|[0-9][A-HJKS-UW])\s*[0-9][ABD-HJLNP-UW-Z]{2})$/i)
      @sources.push "uk_postcode"
      @sources.push "osm_nominatim"
    elsif @query.match(/^[A-Z]\d[A-Z]\s*\d[A-Z]\d$/i)
      @sources.push "ca_postcode"
      @sources.push "osm_nominatim"
    else
      @sources.push "osm_nominatim"
      @sources.push "geonames"
    end

    if @query == "" then
      render :update do |page|
        page.replace_html :sidebar_content, :partial => "search"
      end
    else
    render :update do |page|
      page.replace_html :sidebar_content, :partial => "search"
       page.call "openSidebar"
    end
    end
  end

  def search_latlon
    # get query parameters
    query = params[:query]

    # create result array
    @results = Array.new

    # decode the location
    if m = query.match(/^\s*([+-]?\d+(\.\d*)?)\s*[\s,]\s*([+-]?\d+(\.\d*)?)\s*$/)
      lat = m[1].to_f
      lon = m[3].to_f
    end

    # generate results
    if lat < -90 or lat > 90
      @error = "Latitude #{lat} out of range"
      render :action => "error"
    elsif lon < -180 or lon > 180
      @error = "Longitude #{lon} out of range"
      render :action => "error"
    else
      @results.push({:lat => lat, :lon => lon,
                     :zoom => POSTCODE_ZOOM,
                     :name => "#{lat}, #{lon}"})

      render :action => "results"
    end
  end

  def search_us_postcode
    # get query parameters
    query = params[:query]

    # create result array
    @results = Array.new

    # ask geocoder.us (they have a non-commercial use api)
    response = fetch_text("http://rpc.geocoder.us/service/csv?zip=#{escape_query(query)}")

    # parse the response
    unless response.match(/couldn't find this zip/)
      data = response.split(/\s*,\s+/) # lat,long,town,state,zip
      @results.push({:lat => data[0], :lon => data[1],
                     :zoom => POSTCODE_ZOOM,
                     :prefix => "#{data[2]}, #{data[3]},",
                     :name => data[4]})
    end

    render :action => "results"
  rescue Exception => ex
    @error = "Error contacting rpc.geocoder.us: #{ex.to_s}"
    render :action => "error"
  end

  def search_uk_postcode
    # get query parameters
    query = params[:query]

    # create result array
    @results = Array.new

    # ask npemap.org.uk to do a combined npemap + freethepostcode search
    response = fetch_text("http://www.npemap.org.uk/cgi/geocoder.fcgi?format=text&postcode=#{escape_query(query)}")

    # parse the response
    unless response.match(/Error/)
      dataline = response.split(/\n/)[1]
      data = dataline.split(/,/) # easting,northing,postcode,lat,long
      postcode = data[2].gsub(/'/, "")
      zoom = POSTCODE_ZOOM - postcode.count("#")
      @results.push({:lat => data[3], :lon => data[4], :zoom => zoom,
                     :name => postcode})
    end

    render :action => "results"
  rescue Exception => ex
    @error = "Error contacting www.npemap.org.uk: #{ex.to_s}"
    render :action => "error"
  end

  def search_ca_postcode
    # get query parameters
    query = params[:query]
    @results = Array.new

    # ask geocoder.ca (note - they have a per-day limit)
    response = fetch_xml("http://geocoder.ca/?geoit=XML&postal=#{escape_query(query)}")

    # parse the response
    if response.get_elements("geodata/error").empty?
      @results.push({:lat => response.get_text("geodata/latt").to_s,
                     :lon => response.get_text("geodata/longt").to_s,
                     :zoom => POSTCODE_ZOOM,
                     :name => query.upcase})
    end

    render :action => "results"
  rescue Exception => ex
    @error = "Error contacting geocoder.ca: #{ex.to_s}"
    render :action => "error"
  end

  def search_osm_namefinder
    # get query parameters
    query = params[:query]

    # create result array
    @results = Array.new

    # ask OSM namefinder
    response = fetch_xml("http://gazetteer.openstreetmap.org/namefinder/search.xml?find=#{escape_query(query)}")

    # parse the response
    response.elements.each("searchresults/named") do |named|
      lat = named.attributes["lat"].to_s
      lon = named.attributes["lon"].to_s
      zoom = named.attributes["zoom"].to_s
      place = named.elements["place/named"] || named.elements["nearestplaces/named"]
      type = named.attributes["info"].to_s.capitalize
      name = named.attributes["name"].to_s
      description = named.elements["description"].to_s

      if name.empty?
        prefix = ""
        name = type
      else
        prefix =  t "geocoder.search_osm_namefinder.prefix", :type => type
      end

      if place
        distance = format_distance(place.attributes["approxdistance"].to_i)
        direction = format_direction(place.attributes["direction"].to_i)
        placename = format_name(place.attributes["name"].to_s)
        suffix = t "geocoder.search_osm_namefinder.suffix_place", :distance => distance, :direction => direction, :placename => placename

        if place.attributes["rank"].to_i <= 30
          parent = nil
          parentrank = 0
          parentscore = 0

          place.elements.each("nearestplaces/named") do |nearest|
            nearestrank = nearest.attributes["rank"].to_i
            nearestscore = nearestrank / nearest.attributes["distance"].to_f

            if nearestrank > 30 and
               ( nearestscore > parentscore or
                 ( nearestscore == parentscore and nearestrank > parentrank ) )
              parent = nearest
              parentrank = nearestrank
              parentscore = nearestscore
            end
          end

          if parent
            parentname = format_name(parent.attributes["name"].to_s)

            if  place.attributes["info"].to_s == "suburb"
              suffix = t "geocoder.search_osm_namefinder.suffix_suburb", :suffix => suffix, :parentname => parentname
            else
              parentdistance = format_distance(parent.attributes["approxdistance"].to_i)
              parentdirection = format_direction(parent.attributes["direction"].to_i)
              suffix = t "geocoder.search_osm_namefinder.suffix_parent", :suffix => suffix, :parentdistance => parentdistance, :parentdirection => parentdirection, :parentname => parentname
            end
          end
        end
      else
        suffix = ""
      end

      @results.push({:lat => lat, :lon => lon, :zoom => zoom,
                     :prefix => prefix, :name => name, :suffix => suffix,
                     :description => description})
    end

    render :action => "results"
  rescue Exception => ex
    @error = "Error contacting gazetteer.openstreetmap.org: #{ex.to_s}"
    render :action => "error"
  end

  def search_osm_nominatim
    # get query parameters
    query = params[:query]
    minlon = params[:minlon]
    minlat = params[:minlat]
    maxlon = params[:maxlon]
    maxlat = params[:maxlat]

    # get view box
    if minlon && minlat && maxlon && maxlat
      viewbox = "&viewbox=#{minlon},#{maxlat},#{maxlon},#{minlat}"
    end

    # get objects to excude
    if params[:exclude]
      exclude = "&exclude_place_ids=#{params[:exclude].join(',')}"
    end

    # ask nominatim
    response = fetch_xml("#{NOMINATIM_URL}search?format=xml&q=#{escape_query(query)}#{viewbox}#{exclude}&accept-language=#{request.user_preferred_languages.join(',')}")

    # create result array
    @results = Array.new

    # create parameter hash for "more results" link
    @more_params = params.reverse_merge({ :exclude => [] })

    # extract the results from the response
    results =  response.elements["searchresults"]

    # parse the response
    results.elements.each("place") do |place|
      lat = place.attributes["lat"].to_s
      lon = place.attributes["lon"].to_s
      klass = place.attributes["class"].to_s
      type = place.attributes["type"].to_s
      name = place.attributes["display_name"].to_s
      min_lat,max_lat,min_lon,max_lon = place.attributes["boundingbox"].to_s.split(",")
      prefix_name = t "geocoder.search_osm_nominatim.prefix.#{klass}.#{type}", :default => type.gsub("_", " ").capitalize
      prefix = t "geocoder.search_osm_nominatim.prefix_format", :name => prefix_name

      @results.push({:lat => lat, :lon => lon,
                     :min_lat => min_lat, :max_lat => max_lat,
                     :min_lon => min_lon, :max_lon => max_lon,
                     :prefix => prefix, :name => name})
      @more_params[:exclude].push(place.attributes["place_id"].to_s)
    end

    render :action => "results"
  rescue Exception => ex
    @error = "Error contacting nominatim.openstreetmap.org: #{ex.to_s}"
    render :action => "error"
  end

  def search_geonames
    # get query parameters
    query = params[:query]

    # create result array
    @results = Array.new

    # ask geonames.org
    response = fetch_xml("http://ws.geonames.org/search?q=#{escape_query(query)}&maxRows=20")

    # parse the response
    response.elements.each("geonames/geoname") do |geoname|
      lat = geoname.get_text("lat").to_s
      lon = geoname.get_text("lng").to_s
      name = geoname.get_text("name").to_s
      country = geoname.get_text("countryName").to_s
      @results.push({:lat => lat, :lon => lon,
                     :zoom => GEONAMES_ZOOM,
                     :name => name,
                     :suffix => ", #{country}"})
    end

    render :action => "results"
  rescue Exception => ex
    @error = "Error contacting ws.geonames.org: #{ex.to_s}"
    render :action => "error"
  end

  def description
    @sources = Array.new

    @sources.push({ :name => "osm_nominatim" })
    @sources.push({ :name => "geonames" })

    render :update do |page|
      page.replace_html :sidebar_content, :partial => "description"
      page.call "openSidebar"
    end
  end

  def description_osm_namefinder
    # get query parameters
    lat = params[:lat]
    lon = params[:lon]
    types = params[:types]
    max = params[:max]

    # create result array
    @results = Array.new

    # ask OSM namefinder
    response = fetch_xml("http://gazetteer.openstreetmap.org/namefinder/search.xml?find=#{types}+near+#{lat},#{lon}&max=#{max}")

    # parse the response
    response.elements.each("searchresults/named") do |named|
      lat = named.attributes["lat"].to_s
      lon = named.attributes["lon"].to_s
      zoom = named.attributes["zoom"].to_s
      place = named.elements["place/named"] || named.elements["nearestplaces/named"]
      type = named.attributes["info"].to_s
      name = named.attributes["name"].to_s
      description = named.elements["description"].to_s
      distance = format_distance(place.attributes["approxdistance"].to_i)
      direction = format_direction((place.attributes["direction"].to_i - 180) % 360)
      prefix = t "geocoder.description_osm_namefinder.prefix", :distance => distance, :direction => direction, :type => type
      @results.push({:lat => lat, :lon => lon, :zoom => zoom,
                     :prefix => prefix.capitalize, :name => name,
                     :description => description})
    end

    render :action => "results"
  rescue Exception => ex
    @error = "Error contacting gazetteer.openstreetmap.org: #{ex.to_s}"
    render :action => "error"
  end

  def description_osm_nominatim
    # get query parameters
    lat = params[:lat]
    lon = params[:lon]
    zoom = params[:zoom]

    # create result array
    @results = Array.new

    # ask OSM namefinder
    response = fetch_xml("#{NOMINATIM_URL}reverse?lat=#{lat}&lon=#{lon}&zoom=#{zoom}&accept-language=#{request.user_preferred_languages.join(',')}")

    # parse the response
    response.elements.each("reversegeocode/result") do |result|
      description = result.get_text.to_s

      @results.push({:prefix => "#{description}"})
    end

    render :action => "results"
  rescue Exception => ex
    @error = "Error contacting nominatim.openstreetmap.org: #{ex.to_s}"
    render :action => "error"
  end

  def description_geonames
    # get query parameters
    lat = params[:lat]
    lon = params[:lon]

    # create result array
    @results = Array.new

    # ask geonames.org
    response = fetch_xml("http://ws.geonames.org/countrySubdivision?lat=#{lat}&lng=#{lon}")

    # parse the response
    response.elements.each("geonames/countrySubdivision") do |geoname|
      name = geoname.get_text("adminName1").to_s
      country = geoname.get_text("countryName").to_s
      @results.push({:prefix => "#{name}, #{country}"})
    end

    render :action => "results"
  rescue Exception => ex
    @error = "Error contacting ws.geonames.org: #{ex.to_s}"
    render :action => "error"
  end

private

  def fetch_text(url)
    return Net::HTTP.get(URI.parse(url))
  end

  def fetch_xml(url)
    return REXML::Document.new(fetch_text(url))
  end

  def format_distance(distance)
    return t("geocoder.distance", :count => distance)
  end

  def format_direction(bearing)
    return t("geocoder.direction.south_west") if bearing >= 22.5 and bearing < 67.5
    return t("geocoder.direction.south") if bearing >= 67.5 and bearing < 112.5
    return t("geocoder.direction.south_east") if bearing >= 112.5 and bearing < 157.5
    return t("geocoder.direction.east") if bearing >= 157.5 and bearing < 202.5
    return t("geocoder.direction.north_east") if bearing >= 202.5 and bearing < 247.5
    return t("geocoder.direction.north") if bearing >= 247.5 and bearing < 292.5
    return t("geocoder.direction.north_west") if bearing >= 292.5 and bearing < 337.5
    return t("geocoder.direction.west")
  end

  def format_name(name)
    return name.gsub(/( *\[[^\]]*\])*$/, "")
  end

  def count_results(results)
    count = 0

    results.each do |source|
      count += source[:results].length if source[:results]
    end

    return count
  end

  def escape_query(query)
    return URI.escape(query, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]", false, 'N'))
  end
end
