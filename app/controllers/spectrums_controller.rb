require 'will_paginate/array'
class SpectrumsController < ApplicationController
  respond_to :html, :xml, :js, :csv, :json
  # expand this:
  protect_from_forgery :only => [:clone_calibration, :extract, :calibrate, :save]
  # http://api.rubyonrails.org/classes/ActionController/RequestForgeryProtection/ClassMethods.html
  before_filter :require_login,     :only => [ :new, :edit, :create, :upload, :save, :update, :destroy, :calibrate, :extract, :clone_calibration, :clone, :setsamplerow, :find_brightest_row, :rotate, :reverse, :choose ]

  def stats
  end

  # GET /spectrums
  # GET /spectrums.xml
  def index
    if logged_in?
      redirect_to "/dashboard"
    else
      @spectrums = Spectrum.select("title, created_at, id, user_id, author, photo_file_name, like_count, photo_content_type").order('created_at DESC').where('user_id != 0').paginate(:page => params[:page],:per_page => 24)

      @sets = SpectraSet.find(:all,:limit => 4,:order => "created_at DESC")
      @comments = Comment.all :limit => 12, :order => "id DESC"

      respond_with(@spectrums) do |format|
        format.html {
          render :template => "spectrums/index"
        } # show.html.erb
        format.xml  { render :xml => @spectrums }
      end
    end
  end

  # returns a list of spectrums by tag in a partial for use in macros and tools
  def choose
    
    # accept wildcards
    if params[:id] && params[:id].last == "*"
      comparison = "LIKE"
      params[:id].chop!
      params[:id] += "%"
    else
      comparison = "="
    end

    # user's own spectra
    params[:author] = current_user.login if logged_in? && params[:own]

    @spectrums = Spectrum.order('spectrums.id DESC')
                         .select("DISTINCT(spectrums.id), spectrums.title, spectrums.created_at, spectrums.user_id, spectrums.author, spectrums.calibrated")
                         .joins(:tags)
                         .paginate(:page => params[:page],:per_page => 6)

    # exclude self:
    @spectrums = @spectrums.where('spectrums.id != ?', params[:not]) if params[:not]
    unless params[:id] == "all" || params[:id].nil?
      @spectrums = @spectrums.where('tags.name '+comparison+' (?)', params[:id])
      if params[:author]
        author = User.find_by_login params[:author]
        @spectrums = @spectrums.where(user_id: author.id)
      end
    end

    if @spectrums.length > 0
      render partial: "macros/spectra", locals: { spectrums: @spectrums }
    else
      render text: "<p>No results</p>"
    end
  end

  # eventually start selecting everything but spectrum.data, as show2 
  # doesn't use this to fetch data, but makes a 2nd call. 
  # However, format.json does use it!
  def show
    @spectrum = Spectrum.find(params[:id])
    respond_with(@spectrum) do |format|
      format.html {
        if logged_in?
          @spectra = Spectrum.find(:all, :limit => 12, :order => "created_at DESC", :conditions => ["id != ? AND author = ?",@spectrum.id,current_user.login])
        else
          @spectra = Spectrum.find(:all, :limit => 12, :order => "created_at DESC", :conditions => ["id != ?",@spectrum.id])
        end
        @sets = @spectrum.sets
        @user_sets = SpectraSet.where(author: current_user.login).limit(20).order("created_at DESC") if logged_in?
        @macros = Macro.find :all, :conditions => {:macro_type => "analyze"}
        @calibrations = current_user.calibrations.select { |s| s.id != @spectrum.id } if logged_in?
        @comment = Comment.new
      }
      format.xml  { render :xml => @spectrum }
      format.csv  {
        render :text => SpectrumsHelper.show_csv(@spectrum)
      }
      format.json  {
        render :json => @spectrum.json
      }
    end
  end

  def show2
    show
  end

  def anonymous
    @spectrums = Spectrum.paginate(:order => "created_at DESC", :conditions => {:author => "anonymous"}, :page => params[:page])
    render :template => "spectrums/search"
  end

  def embed
    @spectrum = Spectrum.find(params[:id])
    @width = (params[:width] || 500).to_i
    @height = (params[:height] || 300).to_i
    render :layout => false
  end

  def embed2
    @spectrum = Spectrum.find(params[:id])
    render :template => 'embed/spectrum', :layout => 'embed'
  end

  def search
    params[:id] = params[:q].to_s if params[:id].nil?
    @spectrums = Spectrum.where('title LIKE ?',params[:id]+"%").order("id DESC").paginate(:page => params[:page], :per_page => 24)
    if params[:capture]
      render :partial => "capture/results", :layout => false
    else
      @sets = SpectraSet.where('title LIKE ? OR notes LIKE ?',"%"+params[:id]+"%", "%"+params[:id]+"%").order("id DESC").paginate(:page => params[:set_page])
    end
  end

  def recent
    @spectrums = Spectrum.find(:all, :limit => 10, :order => "id DESC")
    render :partial => "capture/results", :layout => false if params[:capture]
  end

  # GET /spectrums/new
  # GET /spectrums/new.xml
  def new
    @spectrum = Spectrum.new
 
    respond_with(@spectrum) do |format|
      format.html {}
      format.xml  { render :xml => @spectrum }
    end
  end

  # GET /spectrums/1/edit
  def edit
    @spectrum = Spectrum.find(params[:id])
    require_ownership(@spectrum)
  end

  # POST /spectrums
  # POST /spectrums.xml
  # ?spectrum[title]=TITLE&spectrum[author]=anonymous&startWavelength=STARTW&endWavelength=ENDW;
  # replacing this with capture/save soon
  def create

    if params[:dataurl] # mediastream webclient
      @spectrum = Spectrum.new({:title => params[:spectrum][:title],
        :author => current_user.login,
        :video_row => params[:spectrum][:video_row],
        :notes => params[:spectrum][:notes]})
      @spectrum.user_id = current_user.id
      @spectrum.image_from_dataurl(params[:dataurl])
    else # upload form at /upload
      @spectrum = Spectrum.new({:title => params[:spectrum][:title],
        :author => current_user.login,
        :user_id => current_user.id,
        :notes => params[:spectrum][:notes],
        :photo => params[:spectrum][:photo]})
    end

    if @spectrum.save

      respond_with(@spectrum) do |format|

        if (APP_CONFIG["local"] || logged_in?)

          if mobile? || ios?
            @spectrum.save
            @spectrum = Spectrum.find @spectrum.id
            @spectrum.sample_row = @spectrum.find_brightest_row
            #@spectrum.tag("mobile",current_user.id)
          end

          @spectrum.rotate if params[:vertical] == "on"
          @spectrum.tag("iOS",current_user.id) if ios?
          @spectrum.tag(params[:tags],current_user.id) if params[:tags] && params[:tags] != ""
          @spectrum.tag("upload",current_user.id) if params[:upload]
          @spectrum.tag(params[:device],current_user.id) if params[:device] && params[:device] != "none"
          @spectrum.tag("video_row:#{params[:video_row]}", current_user.id) if params[:video_row]
          #@spectrum.tag("sample_row:#{params[:video_row]}", current_user.id) if params[:video_row]

          @spectrum.extract_data

          if params[:spectrum][:calibration_id] && !params[:is_calibration] && params[:spectrum][:calibration_id] != "calibration" && params[:spectrum][:calibration_id] != "undefined"
            @spectrum.clone_calibration(params[:spectrum][:calibration_id])
            @spectrum.tag("calibration:#{params[:spectrum][:calibration_id]}", current_user.id)
          end

          if params[:geotag]
            @spectrum.lat = params[:lat]
            @spectrum.lon = params[:lon]
          end

          @spectrum.reversed = true if params[:spectrum][:reversed] == "true"

          if @spectrum.save!
            flash[:notice] = 'Spectrum was successfully created.'
            format.html {
              redirect_to spectrum_path(@spectrum)
            }
            format.xml  { render :xml => @spectrum, :status => :created, :location => @spectrum }
          else
            render "spectrums/new"
          end

        else

          format.html { render :action => "new" }
          format.xml  { render :xml => @spectrum.errors, :status => :unprocessable_entity }

        end

      end

    else
      render "spectrums/new"
    end
  end

  # used to upload numerical spectrum data as a new spectrum (untested, no image??)
  def upload
    @spectrum = Spectrum.new({:title => params[:spectrum][:title],
      :author => author,
      :user_id => user_id,
      :notes => params[:spectrum][:notes],
      :data => params[:data],
      :photo => params[:photo]})
    @spectrum.save!
    @spectrum.tag(params[:tags], current_user.id) if params[:tags]
    redirect_to spectrum_path(@spectrum)
  end

  # only ajax/POST accessible for now:
  def save
    @spectrum = Spectrum.find(params[:id])
    require_ownership(@spectrum)
    @spectrum.data = params[:data]
    @spectrum.tag(params[:tags],current_user.id) if params[:tags]
    render :text => @spectrum.save
  end

  # PUT /spectrums/1
  # PUT /spectrums/1.xml
  def update
    @spectrum = Spectrum.find(params[:id])
    require_ownership(@spectrum)

    @spectrum.title = params[:spectrum][:title] unless params[:spectrum][:title].nil?
    @spectrum.notes = params[:spectrum][:notes] unless params[:spectrum][:notes].nil?
    @spectrum.data  = params[:spectrum][:data] unless params[:spectrum][:data].nil?

    # clean this up
    respond_to do |format|
      if @spectrum.save
        if request.xhr?
          format.json  { render :json => @spectrum }
        else
          flash[:notice] = 'Spectrum was successfully updated.'
          format.html { redirect_to(@spectrum) }
          format.xml  { head :ok }
        end
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @spectrum.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /spectrums/1
  # DELETE /spectrums/1.xml
  def destroy
    @spectrum = Spectrum.find(params[:id])
    require_ownership(@spectrum)
    @spectrum.destroy

    flash[:notice] = "Spectrum deleted."
    respond_with(@spectrum) do |format|
      format.html { redirect_to('/') }
      format.xml  { head :ok }
    end
  end

  # Start doing this client side!
  def calibrate
    @spectrum = Spectrum.find(params[:id])
    require_ownership(@spectrum)
    @spectrum.calibrate(params[:x1], params[:w1], params[:x2], params[:w2])
    @spectrum.save
    @spectrum.tag('calibration', current_user.id)

    flash[:notice] = "Great, calibrated! <b>Next steps:</b> sign up on <a href='//publiclab.org/wiki/spectrometer'>the mailing list</a>, or browse/contribute to <a href='//publiclab.org'>Public Lab website</a>"
    redirect_to spectrum_path(@spectrum)
  end

  # Start doing this client side!
  def extract
    @spectrum = Spectrum.find(params[:id])
    require_ownership(@spectrum)
    @spectrum.extract_data
    @spectrum.save
    flash[:warning] = "Now, recalibrate, since you've <a href='//publiclab.org/wiki/spectral-workbench-calibration#Cross+section'>set a new cross-section</a>."
    redirect_to spectrum_path(@spectrum)
  end

  def clone
    @spectrum = Spectrum.find(params[:id])
    @new = @spectrum.dup
    @new.author = current_user.login
    @new.user_id = current_user.id
    @new.photo = @spectrum.photo
    @new.save!
    @new.tag("cloneOf:#{@spectrum.id}", current_user.id)
    # now copy over all tags:
    @spectrum.tags.each do |tag|
      @new.tag(tag.name, tag.user_id) unless tag.name.split(':').first == "cloneOf"
    end
    flash[:notice] = "You successfully cloned <a href='#{spectrum_path(@spectrum)}'>Spectrum ##{@spectrum.id}</a>"
    redirect_to spectrum_path(@new)
  end

  # Copy calibration from an existing calibrated spectrum.
  # Start doing this client side!
  def clone_calibration
    @spectrum = Spectrum.find(params[:id])
    @calibration_clone_source = Spectrum.find(params[:clone_id])
    require_ownership(@spectrum)
    @spectrum.clone_calibration(@calibration_clone_source.id)
    @spectrum.save
    @spectrum.remove_powertags('calibration')
    @spectrum.tag("calibration:#{@calibration_clone_source.id}", current_user.id)
    
    respond_with(@spectrums) do |format|
      format.html {
        flash[:notice] = 'Spectrum was successfully calibrated.'
        redirect_to spectrum_path(@spectrum)
      }
      format.json  { render :json => @spectrum }
    end
  end

  def all
    @spectrums = Spectrum.find(:all).paginate(:page => params[:page])
    respond_with(@spectrums) do |format|
      format.xml  { render :xml => @spectrums }
      format.json  { render :json => @spectrums }
    end
  end

  def rss
    if params[:author]
      @spectrums = Spectrum.find_all_by_author(params[:author],:order => "created_at DESC",:limit => 12).paginate(:page => params[:page])
    else
      @spectrums = Spectrum.find(:all,:order => "created_at DESC",:limit => 12).paginate(:page => params[:page])
    end
    respond_to do |format|
      format.xml
    end
  end

  def plots_rss
    @spectrums = Spectrum.find(:all,:order => "created_at DESC",:limit => 12, :conditions => ["author != ?","anonymous"]).paginate(:page => params[:page])
    render :layout => false
    response.headers["Content-Type"] = "application/xml; charset=utf-8"
  end

  def match
    @spectrum = Spectrum.find params[:id]
    render :text => @spectrum.find_match_in_set(params[:set]).to_json
  end

  # Start doing this client side!
  def setsamplerow
    require 'rubygems'
    require 'RMagick'
    @spectrum = Spectrum.find params[:id]
    require_ownership(@spectrum)
    image = Magick::ImageList.new("public"+(@spectrum.photo.url.split('?')[0]).gsub('%20',' '))
    @spectrum.sample_row = (params[:row].to_f*image.rows)
    @spectrum.extract_data
    @spectrum.save
    flash[:warning] = "If this spectrum image is not perfectly vertical, you may need to recalibrate after <a href='//publiclab.org/wiki/spectral-workbench-calibration#Cross+section'>setting a new cross-section</a>."
    redirect_to spectrum_path(@spectrum)
  end

  # Start doing this client side!
  def find_brightest_row
    @spectrum = Spectrum.find params[:id]
    require_ownership(@spectrum)
    @spectrum.sample_row = @spectrum.find_brightest_row
    @spectrum.extract_data
    @spectrum.clone_calibration(@spectrum.id) # recover calibration
    @spectrum.save
    flash[:warning] = "If this spectrum image is not perfectly vertical, you may need to recalibrate after <a href='//publiclab.org/wiki/spectral-workbench-calibration#Cross+section'>setting a new cross-section</a>."
    redirect_to spectrum_path(@spectrum)
  end

  # rotates the image and re-extracts it
  def rotate
    @spectrum = Spectrum.find params[:id]
    require_ownership(@spectrum)
    @spectrum.rotate
    @spectrum.extract_data
    @spectrum.clone_calibration(@spectrum.id)
    @spectrum.save
    redirect_to spectrum_path(@spectrum)
  end

  # Just reverses the image, not the data.
  def reverse
    @spectrum = Spectrum.find params[:id]
    require_ownership(@spectrum)
    @spectrum.reversed = !@spectrum.reversed
    @spectrum.toggle_tag('reversed', current_user.id)
    @spectrum.reverse
    @spectrum.save
    redirect_to spectrum_path(@spectrum)
  end

  # search for calibrations to clone from
  def clone_search
    @spectrum = Spectrum.find(params[:id])
    @calibrations = Spectrum.where(calibrated: true)
                            .where('id != ?',@spectrum.id)
                            .where('title LIKE ? OR notes LIKE ? OR author LIKE ?)',"%#{params[:q]}%", "%#{params[:q]}%","%#{params[:q]}%")
                            .limit(20)
                            .order("created_at DESC")
    render :partial => "spectrums/show/clone_results", :layout => false
  end

  def compare_search
    @spectrum = Spectrum.find(params[:id])
    @spectra = Spectrum.where(calibrated: true)
                            .where('id != ?',@spectrum.id)
                            .where('title LIKE ? OR notes LIKE ? OR author LIKE ?)',"%#{params[:q]}%", "%#{params[:q]}%","%#{params[:q]}%")
                            .limit(20)
                            .order("created_at DESC")
    render :partial => "spectrums/show/compare_search", :layout => false
  end

  def set_search
    @spectrum = Spectrum.find(params[:id])
    @user_sets = SpectraSet.where('author = ? AND (title LIKE ? OR notes LIKE ?)',current_user.login,"%#{params[:q]}%", "%#{params[:q]}%")
                           .limit(20)
                           .order('created_at DESC')
    @user_sets = current_user.sets if logged_in?
    render :partial => "spectrums/show/set_results", :layout => false
  end

end
