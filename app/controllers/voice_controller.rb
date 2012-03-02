require 'pp'
require 'json'
require 'apns'
require 'xmlsimple'
require 'date'
require 'chronic'
require 'twiliolib'
require 'twilio-ruby'
require 'pp'

class VoiceController < ApplicationController
  skip_before_filter :verify_authenticity_token
  def recieve
    course = Course.find(params[:course_id].to_s)
    response = Twilio::TwiML::Response.new do |r|
      d = DataStore.create({:name=>"call_"+params[:CallSid],:data=>{"course"=>course.id,"text"=>"monday","voice"=>"10:15"}.to_json})
      greeting = 'Welcome to Deep Cliff Golf Course.  To book a Tee Time, press 1.  To speak with the course, press 2'
      r.Gather :action => "/voice/options" do |d|
        d.Say greeting, :voice => 'man'
      end

    end
    render :text => response.text
  end
  
  def options
    response = Twilio::TwiML::Response.new do |r|

      if params[:Digits] == "1"
        r.Say "Now say something like .. next tuesday at 2pm for 4 golfers ", :voice => 'man'
        r.Record :action => "/voice/getdate", :transcribeCallback => '/voice/transcribe_callback', :maxLength => 7, :timeout => 2
      else
        r.Say "Too bad, you lose", :voice => 'woman'
      end
    end
    render :text => response.text
  end
  
  def transcribe_callback
    d = DataStore.find_by_name("call_"+params[:CallSid])
    data = JSON.parse(d.data)
    data["text"]  = params[:TranscriptionText]
    data["voice"] = params[:RecordingUrl]
    
    split = data["text"].split(" ")
    
    golfers = "2"
    xdate = nil
    time = "2"
    
    days = ["monday","tuesday","wednesday","thursday","friday","saturday","sunday"]
    nexter = false
    count = 0
    substring = ""
    split.each do |s|
      substring += s+" "
      date = Chronic.parse(substring)
      if !date.nil?
        xdate = date
      end
      if s == 'next'
        nexter = true
      end
    end
    reverse = split.reverse
    
    counter = 0
    reverse.each do |r|
      golfers = r.to_i
      counter += 1
      break if golfers > 1 or counter > 3
    end
    
    golfers = golfers.to_s
    
    puts golfers
    puts xdate
    
    data["golfers"] = golfers
    data["date"] = xdate.to_s
    
    
    d.data = data.to_json
    d.save
  end
  
  def getdate
    d = DataStore.find_by_name("call_"+params[:CallSid])
    data = JSON.parse(d.data)

    response = Twilio::TwiML::Response.new do |r|
      r.Say "Please wait about 15 seconds while we process your request", :voice => 'man'
      r.Pause :length=>15
      r.Redirect "/voice/gettime"
    end
    render :text => response.text
    
  end
  
  def get_slots(data)
    course_id    = data["course"]
    dt = Chronic.parse(data["date"])
    time         = dt.strftime("%H:%M")   
    date         = dt.strftime("%Y-%m-%d")
    
    updated_course = Rails.cache.fetch("Updated_Course_"+course_id.to_s) {Course.find(course_id)}
    
    dates = JSON.parse(updated_course.available_times)
    if dates.has_key?(date)
       if dates[date]["hours"].has_key?(time.split(":")[0].to_i.to_s)
         avail   = dates[date]["hours"][time.split(":")[0].to_i.to_s]
       else
         avail   = nil
       end
    else
      avail = nil
    end
    
    return avail
      
      
      
    
  end
  
  def gettime
    d = DataStore.find_by_name("call_"+params[:CallSid])
    data = JSON.parse(d.data)
    puts "Please confirm your slot for "+data["golfers"]+" golfers on "+ Chronic.parse(data["date"]).strftime("%A %B %d")+" at "+Chronic.parse(data["date"]).strftime("%l %p")
    
    slots = get_slots(data)
    
    
    response = Twilio::TwiML::Response.new do |r|
      greeting = "Please choose from the following slots for "+data["golfers"]+" golfers on "+ Chronic.parse(data["date"]).strftime("%A %B %d")+" by pressing the number preceding the slot"
      
      if !slots.nil?
        r.Gather :action => "/voice/book" do |d|
          counter = 0
          slots.each do |slot|
            counter += 1
            d.Say counter.to_s+" "+Chronic.parse(slot["t"]).strftime("%l %p"), :voice => 'man'
            d.Pause :length => 2
          end
        end
      else
        r.Redirect "/voice/options?Digits=1"
      end
      
    end
    render :text => response.text
  end
  
  def book
    d = DataStore.find_by_name("call_"+params[:CallSid])
    data = JSON.parse(d.data)
    dt = Chronic.parse(data["date"])
    date = dt.strftime("%Y-%m-%d")
    slots = get_slots(data)
    slot = slots[params[:Digits].to_i-1]
    total = (slot["p"] * data["golfers"].to_i).to_s
    reservation = Reservation.book_tee_time("carlcwheatley@gmail.com", data["course"], data["golfers"], slot["t"], date, total)
    response = Twilio::TwiML::Response.new do |r|
      greeting = "Thanks for your business, your cost is "+total+" dollars due at course"
      r.Say greeting, :voice => 'man'
    end
    render :text => response.text
  end

end
