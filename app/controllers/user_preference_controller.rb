class UserPreferenceController < ApplicationController
  before_filter :authorize

  def read

    doc = OSM::API.new.get_xml_doc

    prefs = @user.preferences

    el1 = XML::Node.new 'preferences'

    prefs.each do |pref|
      el1 <<  pref.to_xml_node
    end

    doc.root << el1
    render :text => doc.to_s, :content_type => "text/xml"

  end

  def update
    begin
      p = XML::Parser.new
      p.string = request.raw_post
      doc = p.parse

      prefs = []

      keyhash = {}

      doc.find('//preferences/preference').each do |pt|
        pref = UserPreference.new
        
        unless keyhash[pt['k']].nil? # already have that key
          render :text => 'OH NOES! CAN HAS UNIQUE KEYS?', :status => 406
          return
        end
        
        keyhash[pt['k']] = 1

        pref.k = pt['k']
        pref.v = pt['v']
        pref.user_id = @user.id
        prefs << pref
      end

      if prefs.size > 150
        render :text => 'Too many preferences', :status => 413
        return
      end

      # kill the existing ones
      UserPreference.delete_all(['user_id = ?', @user.id])

      # save the new ones
      prefs.each do |pref|
        pref.save!
      end

    rescue Exception => ex
      render :text => 'OH NOES! FAIL!: ' + ex.to_s, :status => 500
      return
    end

    render :nothing => true
  end

end