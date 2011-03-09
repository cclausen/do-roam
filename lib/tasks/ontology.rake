namespace :ontology do
  desc 'Read in OSM ontologies'
  task :read => :environment do
    # delete old stuff and read in ontologies
    Ontology.all.each do |o| o.destroy end
    OntologyMapping.all.each do |o| o.destroy end
    puts "Reading Ontology/activity-eng.owl"
    s = Ontology.read_ontology("Ontology/activity-eng.owl","activities")
    puts "Reading Ontology/tags.owl"
    t = Ontology.read_ontology("Ontology/tags.owl","tags")
    puts "Reading Ontology/map.view"
    om = OntologyMapping.read_mapping("Ontology/map.view","activities2tags",s,t)

  
  
   
#    icon("Strom_aus_nicht_regenerativen_Energien","fuel.png")
#    icon("Strom_aus_regenerativen_Energien","fuelpump.png")

  icon("Education","bildungseinrichtungen.png")
  icon("Bookstore","mall.png")
  icon("Drugstore","mall.png")
  icon("Flowers","florist.png")
  icon("Delicatessen","delicacy.png")
  icon("Camping","hotel.png")
  icon("Guestroom","hotel.png")
  icon("YouthHostel","hotel.png")
  icon("Church","christian.png")
  icon("Mosque","muslim.png")
  icon("Synagogue","jewish.png")
  icon("Kindergarten","childcare.png")
  icon("Wellness","fitness.png")
  icon("ChargingStation","plug.png")
  icon("Supermarket","mall.png")
  icon("BicycleRental","bicyclerent.png")
  icon("Electronics","electronics.png")
  icon("PostOffice","post_office.png")
  icon("Furniture","mall.png")
  icon("CarSharing","carsharing.png")
  icon("Stationery","mall.png")
  icon("Pharmacy","pharmacy.png")
  icon("Hospital","hospital.png")
  icon("College","education.png")
  icon("Library","library.png")
  icon("FastFood","fastfood.png")
  icon("BusStop","busstop.png")
  icon("Parking","parking.png")
  icon("Police","police.png")
  icon("Subway","ubahn.png")
  icon("Opera","theatre.png")
  icon("Hairdresser","hairdresser.png")
  icon("Mall","mall.png")
  icon("Toy","mall.png")
  icon("Restaurant","restaurant.png")
  icon("Tram","busstop.png")
  icon("ATM","atm.png")
  icon("Hostel","hostel.png")
  icon("Motel","hotel.png")
  icon("Hotel","hotel.png")
  icon("Cafe","cafe.png")
  icon("University","university.png")
  icon("Shopping","mall.png")
  icon("Clothing","clothes.png")
  icon("SwimmingPool","swimming.png")
  icon("American","restaurant.png")
  icon("Japanese","restaurant.png")
  icon("Cuisine","restaurant.png")
  icon("Theatre","theatre.png")
  icon("Mexican","restaurant.png")
  icon("Turkish","restaurant.png")
  icon("Doctor","doctor.png")
  icon("Italian","restaurant.png")
  icon("Chinese","restaurant.png")
  icon("Spanish","restaurant.png")
  icon("Cinema","cinema.png")
  icon("Museum","museum.png")
  icon("German","restaurant.png")
  icon("French","restaurant.png")
  icon("Indian","restaurant.png")
  icon("Sushi","restaurant.png")
  icon("Pizza","restaurant.png")
  icon("Sauna","restaurant.png")
  icon("Park","park.png")
  icon("Thai","restaurant.png")
  icon("Fish","fish.png")
  icon("Bank","bank.png")
  icon("Shoe","shoes.png")
  icon("Butcher","butcher.png")  

  icon("Minigolf","minigolf.png")
  icon("Ruin","ruins.png")
  icon("Leisure","question-mark.png")
  icon("Landscape","question-mark.png")
  icon("Health","question-mark.png")
  icon("PublicTransport","question-mark.png")
  icon("SportAndFitness","question-mark.png")
  icon("Vegetarian","restaurant.png")
  icon("Forest","forest.png")
  icon("Climbing","climbing.png")
  icon("Computer","computer.png")
  icon("Tourism","question-mark.png")
  icon("Massage","massage.png")
  icon("Soccer","soccer.png")
  icon("Hiking","hiking.png")
  icon("Bakery","bakery.png")
  icon("PlaceOfWorship","question-mark.png")
  icon("Greek","restaurant.png")
  icon("Dance","dance.png")
  icon("GolfCourse","golfcourse.png")
  icon("Optician","optician.png")
  icon("Valley","question-mark.png")
  icon("Castle","castles.png")
  icon("River","river.png")
  icon("Finance","question-mark.png")
  icon("TravelAgency","travelagency.png")
  icon("FitnessStudio","fitness.png")
  icon("InformationService","question-mark.png")
  icon("Bowling","bowling.png")


# not needed
  icon("Address","question-mark.png")
  icon("OpeningHours","question-mark.png")

    # mark mapped classes that have an icon as interesting
    om.ontology_mapping_elements.each do |m|
      c = m.source
      if !c.iconfile.nil? and !c.iconfile.empty?
        c.mark_interesting
      end
    end
  end
end

namespace :intervals do
  desc 'Read in opening hours'
  task :read => :environment do
    NodeTag.find(:all,:conditions=>{:k=>"opening_hours"}).each do |nt|
      puts "nodetag # #{nt.id}"
      Interval.parse_many(nt.v).each do |i|
        NodeTagInterval.create(:node_tag_id => nt.id, :interval_id => i.id)
      end
    end
  end
end

namespace :map do
  desc 'Read in OSM data for Bremen'
  task :read_bremen => :environment do
    system "wget http://download.geofabrik.de/osm/europe/germany/bremen.osm.bz2"
    system 'osmosis --read-xml-0.6 file="bremen.osm.bz2" --write-apidb-0.6 populateCurrentTables=yes host="localhost" database="openstreetmap" user="openstreetmap" password="openstreetmap" validateSchemaVersion=no'
  end
end  

  def self.icon(cname,file)
    c=OntologyClass.find_by_name(cname)
    if !c.nil?
      c.iconfile = file
      c.save
    else
      puts "#{cname} not found"
    end  
  end  
  