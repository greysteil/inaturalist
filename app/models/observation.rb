#encoding: utf-8
class Observation < ActiveRecord::Base

  include ActsAsElasticModel
  include ObservationSearch
  include ActsAsUUIDable

  has_subscribers :to => {
    :comments => {:notification => "activity", :include_owner => true},
    :identifications => {:notification => "activity", :include_owner => true}
  }
  notifies_subscribers_of :user, :notification => "created_observations",
    :queue_if => lambda { |observation| !observation.bulk_import }
  
  # Why aren't we using after_save? Because we need this to run before the
  # after_create created by notifiesi_subscribers_of :public_places runs
  after_create :update_observations_places
  after_update :update_observations_places
  
  notifies_subscribers_of :public_places, :notification => "new_observations", 
    :on => :create,
    :queue_if => lambda {|observation|
      observation.georeferenced? && !observation.bulk_import
    },
    :if => lambda {|observation, place, subscription|
      return false unless observation.georeferenced?
      return true if subscription.taxon_id.blank?
      return false if observation.taxon.blank?
      observation.taxon.ancestor_ids.include?(subscription.taxon_id)
    }
  notifies_subscribers_of :taxon_and_ancestors, :notification => "new_observations", 
    :queue_if => lambda {|observation| !observation.taxon_id.blank? && !observation.bulk_import},
    :if => lambda {|observation, taxon, subscription|
      return true if observation.taxon_id == taxon.id
      return false if observation.taxon.blank?
      observation.taxon.ancestor_ids.include?(subscription.resource_id)
    }
  notifies_users :mentioned_users,
    except: :previously_mentioned_users,
    on: :save,
    notification: "mention",
    delay: false,
    if: lambda {|u| u.prefers_receive_mentions? }
  acts_as_taggable
  acts_as_votable
  acts_as_spammable fields: [ :description ],
                    comment_type: "item-description",
                    automated: false
  include Ambidextrous
  
  # Set to true if you want to skip the expensive updating of all the user's
  # lists after saving.  Useful if you're saving many observations at once and
  # you want to update lists in a batch
  attr_accessor :skip_refresh_lists, :skip_refresh_check_lists, :skip_identifications,
    :bulk_import, :skip_indexing, :editing_user_id, :skip_quality_metrics, :bulk_delete
  
  # Set if you need to set the taxon from a name separate from the species 
  # guess
  attr_accessor :taxon_name
  
  # licensing extras
  attr_accessor :make_license_default
  attr_accessor :make_licenses_same
  
  # coordinate system
  attr_accessor :coordinate_system
  attr_accessor :geo_x
  attr_accessor :geo_y

  attr_accessor :owners_identification_from_vision_requested
  attr_accessor :localize_locale
  attr_accessor :localize_place
  
  def captive_flag
    @captive_flag ||= !quality_metrics.detect{|qm| 
      qm.user_id == user_id && qm.metric == QualityMetric::WILD && !qm.agree?
    }.nil?
  end

  def captive_flag=(v)
    @captive_flag = v
  end
  attr_accessor :force_quality_metrics

  # custom project field errors
  attr_accessor :custom_field_errors
  
  MASS_ASSIGNABLE_ATTRIBUTES = [:make_license_default, :make_licenses_same]
  
  M_TO_OBSCURE_THREATENED_TAXA = 10000
  OUT_OF_RANGE_BUFFER = 5000 # meters
  PLANETARY_RADIUS = 6370997.0
  DEGREES_PER_RADIAN = 57.2958
  FLOAT_REGEX = /[-+]?[0-9]*\.?[0-9]+/
  COORDINATE_REGEX = /[^\d\,]*?(#{FLOAT_REGEX})[^\d\,]*?/
  LAT_LON_SEPARATOR_REGEX = /[\,\s]\s*/
  LAT_LON_REGEX = /#{COORDINATE_REGEX}#{LAT_LON_SEPARATOR_REGEX}#{COORDINATE_REGEX}/
  COORDINATE_UNCERTAINTY_CELL_SIZE = 0.2

  OPEN = "open"
  PRIVATE = "private"
  OBSCURED = "obscured"
  GEOPRIVACIES = [OBSCURED, PRIVATE]
  GEOPRIVACY_DESCRIPTIONS = {
    OPEN => :open_description,
    OBSCURED => :obscured_description, 
    PRIVATE => :private_description
  }
  RESEARCH_GRADE = "research"
  CASUAL = "casual"
  NEEDS_ID = "needs_id"
  QUALITY_GRADES = [CASUAL, NEEDS_ID, RESEARCH_GRADE]

  COMMUNITY_TAXON_SCORE_CUTOFF = (2.0 / 3)
  
  LICENSES = [
    ["CC0", :cc_0_name, :cc_0_description],
    ["CC-BY", :cc_by_name, :cc_by_description],
    ["CC-BY-NC", :cc_by_nc_name, :cc_by_nc_description],
    ["CC-BY-SA", :cc_by_sa_name, :cc_by_sa_description],
    ["CC-BY-ND", :cc_by_nd_name, :cc_by_nd_description],
    ["CC-BY-NC-SA",:cc_by_nc_sa_name, :cc_by_nc_sa_description],
    ["CC-BY-NC-ND", :cc_by_nc_nd_name, :cc_by_nc_nd_description]
  ]
  LICENSE_CODES = LICENSES.map{|row| row.first}
  LICENSES.each do |code, name, description|
    const_set code.gsub(/\-/, '_'), code
  end
  PREFERRED_LICENSES = [CC_BY, CC_BY_NC, CC0]
  CSV_COLUMNS = [
    "id", 
    "species_guess",
    "scientific_name", 
    "common_name", 
    "iconic_taxon_name",
    "taxon_id",
    "id_please",
    "num_identification_agreements",
    "num_identification_disagreements",
    "observed_on_string",
    "observed_on", 
    "time_observed_at",
    "time_zone",
    "place_guess",
    "latitude", 
    "longitude",
    "positional_accuracy",
    "private_place_guess",
    "private_latitude",
    "private_longitude",
    "private_positional_accuracy",
    "geoprivacy",
    "coordinates_obscured",
    "positioning_method",
    "positioning_device",
    "out_of_range",
    "user_id", 
    "user_login",
    "created_at",
    "updated_at",
    "quality_grade",
    "license",
    "url", 
    "image_url",
    "sound_url",
    "tag_list",
    "description",
    "oauth_application_id",
    "captive_cultivated"
  ]
  BASIC_COLUMNS = [
    "id", 
    "observed_on_string",
    "observed_on", 
    "time_observed_at",
    "time_zone",
    "out_of_range",
    "user_id", 
    "user_login",
    "created_at",
    "updated_at",
    "quality_grade",
    "license",
    "url", 
    "image_url",
    "sound_url",
    "tag_list",
    "description",
    "id_please",
    "num_identification_agreements",
    "num_identification_disagreements",
    "captive_cultivated",
    "oauth_application_id"
  ]
  GEO_COLUMNS = [
    "place_guess",
    "latitude", 
    "longitude",
    "positional_accuracy",
    "private_place_guess",
    "private_latitude",
    "private_longitude",
    "private_positional_accuracy",
    "geoprivacy",
    "coordinates_obscured",
    "positioning_method",
    "positioning_device",
    "place_town_name",
    "place_county_name",
    "place_state_name",
    "place_country_name",
    "place_admin1_name",
    "place_admin2_name"
  ]
  TAXON_COLUMNS = [
    "species_guess",
    "scientific_name", 
    "common_name", 
    "iconic_taxon_name",
    "taxon_id"
  ]
  EXTRA_TAXON_COLUMNS = %w(
    kingdom
    phylum
    subphylum
    superclass
    class
    subclass
    superorder
    order
    suborder
    superfamily
    family
    subfamily
    supertribe
    tribe
    subtribe
    genus
    genushybrid
    species
    hybrid
    subspecies
    variety
    form
  ).map{|r| "taxon_#{r}_name"}.compact
  ALL_EXPORT_COLUMNS = (CSV_COLUMNS + BASIC_COLUMNS + GEO_COLUMNS + TAXON_COLUMNS + EXTRA_TAXON_COLUMNS).uniq
  WGS84_PROJ4 = "+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"
  ALLOWED_DESCRIPTION_TAGS = %w(a abbr acronym b blockquote br cite em i img pre s small strike strong sub sup)

  preference :community_taxon, :boolean, :default => nil
  
  belongs_to :user
  belongs_to :taxon
  belongs_to :community_taxon, :class_name => 'Taxon'
  belongs_to :iconic_taxon, :class_name => 'Taxon', 
                            :foreign_key => 'iconic_taxon_id'
  belongs_to :oauth_application
  belongs_to :site, :inverse_of => :observations
  has_many :observation_photos, -> { order("id asc") }, :dependent => :destroy, :inverse_of => :observation
  has_many :photos, :through => :observation_photos
  
  # note last_observation and first_observation on listed taxa will get reset 
  # by CheckList.refresh_with_observation
  has_many :listed_taxa, :foreign_key => 'last_observation_id'
  has_many :first_listed_taxa, :class_name => "ListedTaxon", :foreign_key => 'first_observation_id'
  has_many :first_check_listed_taxa, -> { where("listed_taxa.place_id IS NOT NULL") }, :class_name => "ListedTaxon", :foreign_key => 'first_observation_id'
  
  has_many :comments, :as => :parent, :dependent => :destroy
  has_many :annotations, as: :resource, dependent: :destroy
  has_many :identifications, :dependent => :destroy
  has_many :project_observations, :dependent => :destroy
  has_many :project_observations_with_changes, -> {
    joins(:model_attribute_changes) }, class_name: "ProjectObservation"
  has_many :project_invitations, :dependent => :destroy
  has_many :projects, :through => :project_observations
  has_many :quality_metrics, :dependent => :destroy
  has_many :observation_field_values, -> { order("id asc") }, :dependent => :destroy, :inverse_of => :observation
  has_many :observation_fields, :through => :observation_field_values
  has_many :observation_links
  has_and_belongs_to_many :posts
  has_many :observation_sounds, :dependent => :destroy, :inverse_of => :observation
  has_many :sounds, :through => :observation_sounds
  # not using dependent: :destroy for observations_places
  # since that table has no ID column and Rails expect it
  has_many :observations_places
  has_many :observation_reviews, :dependent => :destroy
  has_many :confirmed_reviews, -> { where("observation_reviews.reviewed = true") },
    class_name: "ObservationReview"

  FIELDS_TO_SEARCH_ON = %w(names tags description place)
  NON_ELASTIC_ATTRIBUTES = %w(establishment_means em)

  accepts_nested_attributes_for :observation_field_values, 
    :allow_destroy => true, 
    :reject_if => lambda { |attrs| attrs[:value].blank? }
  
  ##
  # Validations
  #
  validates_presence_of :user_id
  
  validate :must_be_in_the_past,
           :must_not_be_a_range

  validates_numericality_of :latitude,
    :allow_blank => true, 
    :less_than_or_equal_to => 90, 
    :greater_than_or_equal_to => -90
  validates_numericality_of :longitude,
    :allow_blank => true, 
    :less_than_or_equal_to => 180, 
    :greater_than_or_equal_to => -180
  validates_length_of :observed_on_string, :maximum => 256, :allow_blank => true
  validates_length_of :species_guess, :maximum => 256, :allow_blank => true
  validates_length_of :place_guess, :maximum => 256, :allow_blank => true
  validate do
    # This should be a validation on cached_tag_list, but acts_as_taggable seems
    # to set that after the validations run
    if tag_list.join(", ").length > 750
      errors.add( :tag_list, "must be under 750 characters total, no more than 256 characters per tag" )
    end
  end
  validate do
    unless coordinate_system.blank?
      begin
        RGeo::CoordSys::Proj4.new( coordinate_system )
      rescue RGeo::Error::UnsupportedOperation
        errors.add( :coordinate_system, "is not a valid Proj4 string" )
      end
    end
  end
  # See /config/locale/en.yml for field labels for `geo_x` and `geo_y`
  validates_numericality_of :geo_x,
    :allow_blank => true,
    :message => "should be a number"
  validates_numericality_of :geo_y,
    :allow_blank => true,
    :message => "should be a number"
  validates_presence_of :geo_x, :if => proc {|o| o.geo_y.present? }
  validates_presence_of :geo_y, :if => proc {|o| o.geo_x.present? }
  
  before_validation :munge_observed_on_with_chronic,
                    :set_time_zone,
                    :set_time_in_time_zone,
                    :set_coordinates

  before_create :replace_inactive_taxon
  before_save :strip_species_guess,
              :set_taxon_from_species_guess,
              :set_taxon_from_taxon_name,
              :keep_old_taxon_id,
              :set_latlon_from_place_guess,
              :reset_private_coordinates_if_coordinates_changed,
              :normalize_geoprivacy,
              :set_license,
              :trim_user_agent,
              :update_identifications,
              :set_community_taxon_before_save,
              :set_taxon_from_probable_taxon,
              :obscure_coordinates_for_geoprivacy,
              :obscure_coordinates_for_threatened_taxa,
              :set_geom_from_latlon,
              :set_place_guess_from_latlon,
              :obscure_place_guess,
              :set_iconic_taxon

  before_update :set_quality_grade

  after_save :refresh_lists,
             :refresh_check_lists,
             :update_out_of_range_later,
             :update_default_license,
             :update_all_licenses,
             :update_taxon_counter_caches,
             :update_quality_metrics,
             :update_public_positional_accuracy,
             :update_mappable,
             :set_captive,
             :set_taxon_photo,
             :create_observation_review,
             :reassess_annotations
  after_create :set_uri, :update_user_counter_caches_after_create
  before_destroy :keep_old_taxon_id
  after_destroy :refresh_lists_after_destroy, :refresh_check_lists,
    :update_taxon_counter_caches, :create_deleted_observation,
    :update_user_counter_caches_after_destroy, :delete_observations_places

  after_commit :reindex_identifications, :reindex_places, :reindex_projects
  
  ##
  # Named scopes
  # 
  
  # Area scopes
  # scope :in_bounding_box, lambda { |swlat, swlng, nelat, nelng|
  scope :in_bounding_box, lambda {|*args|
    swlat, swlng, nelat, nelng, options = args
    options ||= {}
    if options[:private]
      geom_col = "observations.private_geom"
      lat_col = "observations.private_latitude"
      lon_col = "observations.private_longitude"
    else
      geom_col = "observations.geom"
      lat_col = "observations.latitude"
      lon_col = "observations.longitude"
    end

    # resort to lat/lon cols for date-line spanning boxes
    if swlng.to_f > 0 && nelng.to_f < 0
      where("#{lat_col} > ? AND #{lat_col} < ? AND (#{lon_col} > ? OR #{lon_col} < ?)", 
        swlat.to_f, nelat.to_f, swlng.to_f, nelng.to_f)
    else
      where("ST_Intersects(
        ST_MakeBox2D(ST_Point(#{swlng.to_f}, #{swlat.to_f}), ST_Point(#{nelng.to_f}, #{nelat.to_f})),
        #{geom_col}
      )")
    end
  } do
    def distinct_taxon
      group("taxon_id").where("taxon_id IS NOT NULL").includes(:taxon)
    end
  end
  
  scope :in_place, lambda {|place|
    place_id = if place.is_a?(Place)
      place.id
    elsif place.to_i == 0
      begin
        Place.find(place).try(&:id)
      rescue ActiveRecord::RecordNotFound
        -1
      end
    else
      place.to_i
    end
    joins("JOIN place_geometries ON place_geometries.place_id = #{place_id}").
    where("ST_Intersects(place_geometries.geom, observations.private_geom)")
  }

  # should use .select("DISTINCT observations.*")
  scope :in_places, lambda {|place_ids|
    joins("JOIN place_geometries ON place_geometries.place_id IN (#{place_ids.join(",")})").
    where("ST_Intersects(place_geometries.geom, observations.private_geom)")
  }

  scope :in_taxons_range, lambda {|taxon|
    taxon_id = taxon.is_a?(Taxon) ? taxon.id : taxon.to_i
    joins("JOIN taxon_ranges ON taxon_ranges.taxon_id = #{taxon_id}").
    where("ST_Intersects(taxon_ranges.geom, observations.private_geom)")
  }
  
  # possibly radius in kilometers
  scope :near_point, Proc.new { |lat, lng, radius|
    lat = lat.to_f
    lng = lng.to_f
    radius = radius.to_f
    radius = 10.0 if radius == 0
    planetary_radius = PLANETARY_RADIUS / 1000 # km
    radius_degrees = radius / (2*Math::PI*planetary_radius) * 360.0
    where("ST_DWithin(ST_Point(?,?), geom, ?)", lng.to_f, lat.to_f, radius_degrees)
  }
  
  # Has_property scopes
  scope :has_taxon, lambda { |*args|
    taxon_id = args.first
    if taxon_id.nil?
      where("taxon_id IS NOT NULL")
    else
      where("taxon_id IN (?)", taxon_id)
    end
  }
  scope :has_iconic_taxa, lambda { |iconic_taxon_ids|
    iconic_taxon_ids = [iconic_taxon_ids].flatten.map do |itid|
      if itid.is_a?(Taxon)
        itid.id
      elsif itid.to_i == 0
        Taxon::ICONIC_TAXA_BY_NAME[itid].try(:id)
      else
        itid
      end
    end.uniq
    if iconic_taxon_ids.include?(nil)
      where(
        "observations.iconic_taxon_id IS NULL OR observations.iconic_taxon_id IN (?)", 
        iconic_taxon_ids
      )
    elsif !iconic_taxon_ids.empty?
      where("observations.iconic_taxon_id IN (?)", iconic_taxon_ids)
    end
  }
  
  scope :has_geo, -> { where("latitude IS NOT NULL AND longitude IS NOT NULL") }
  scope :has_id_please, -> { where( "quality_grade = ?", NEEDS_ID ) }
  scope :has_photos, -> { where("observation_photos_count > 0") }
  scope :has_sounds, -> { where("observation_sounds_count > 0") }
  scope :has_quality_grade, lambda {|quality_grade|
    quality_grades = quality_grade.to_s.split(',') & Observation::QUALITY_GRADES
    quality_grade = '' if quality_grades.size == 0
    where("quality_grade IN (?)", quality_grades)
  }
  
  # Find observations by a taxon object.  Querying on taxa columns forces 
  # massive joins, it's a bit sluggish
  scope :of, lambda { |taxon|
    taxon = Taxon.find_by_id(taxon.to_i) unless taxon.is_a? Taxon
    return where("1 = 2") unless taxon
    c = taxon.descendant_conditions.to_sql
    c[0] = "taxa.id = #{taxon.id} OR #{c[0]}"
    joins(:taxon).where(c)
  }

  scope :with_identifications_of, lambda { |taxon|
    taxon = Taxon.find_by_id( taxon.to_i ) unless taxon.is_a? Taxon
    return where( "1 = 2" ) unless taxon
    c = taxon.descendant_conditions.to_sql
    c = c.gsub( '"taxa"."ancestry"', 'it."ancestry"' )
    # I'm not using TaxonAncestor here b/c updating observations for changes
    # in conservation status uses this scope, and when a cons status changes,
    # we don't want to skip any taxa that have moved around the tree since the
    # last time the denormalizer ran
    select( "DISTINCT observations.*").
    joins( :identifications ).
    joins( "JOIN taxa it ON it.id = identifications.taxon_id" ).
    where( "identifications.current AND (it.id = ? or #{c})", taxon.id ) 
  }
  
  scope :at_or_below_rank, lambda {|rank| 
    rank_level = Taxon::RANK_LEVELS[rank]
    joins(:taxon).where("taxa.rank_level <= ?", rank_level)
  }
  
  # Find observations by user
  scope :by, lambda {|user|
    if user.is_a?(User) || user.to_i > 0
      where("observations.user_id = ?", user)
    else
      joins(:user).where("users.login = ?", user)
    end
  }
  
  # Order observations by date and time observed
  scope :latest, -> { order("observed_on DESC NULLS LAST, time_observed_at DESC NULLS LAST") }
  scope :recently_added, -> { order("observations.id DESC") }
  
  # TODO: Make this work for any SQL order statement, including multiple cols
  scope :order_by, lambda { |order_sql|
    pieces = order_sql.split
    order_by = pieces[0]
    order = pieces[1] || 'ASC'
    extra = [pieces[2..-1]].flatten.join(' ')
    extra = "NULLS LAST" if extra.blank?
    options = {}
    case order_by
    when 'observed_on'
      order "observed_on #{order} #{extra}, time_observed_at #{order} #{extra}"
    when 'created_at'
      order "observations.id #{order} #{extra}"
    when 'project'
      order("project_observations.id #{order} #{extra}").joins(:project_observations)
    when 'votes'
      order("cached_votes_total #{order} #{extra}")
    else
      order "#{order_by} #{order} #{extra}"
    end
  }
  
  def self.identifications(agreement)
    scope = Observation
    scope = scope.includes(:identifications)
    case agreement
    when 'most_agree'
      scope.where("num_identification_agreements > num_identification_disagreements")
    when 'some_agree'
      scope.where("num_identification_agreements > 0")
    when 'most_disagree'
      scope.where("num_identification_agreements < num_identification_disagreements")
    else
      scope
    end
  end
  
  # Time based named scopes
  scope :created_after, lambda { |time| where('created_at >= ?', time)}
  scope :created_before, lambda { |time| where('created_at <= ?', time)}
  scope :updated_after, lambda { |time| where('updated_at >= ?', time)}
  scope :updated_before, lambda { |time| where('updated_at <= ?', time)}
  scope :observed_after, lambda { |time| where('time_observed_at >= ?', time)}
  scope :observed_before, lambda { |time| where('time_observed_at <= ?', time)}
  scope :in_month, lambda {|month| where("EXTRACT(MONTH FROM observed_on) = ?", month)}
  scope :week, lambda {|week| where("EXTRACT(WEEK FROM observed_on) = ?", week)}
  
  scope :in_projects, lambda { |projects|
    # NOTE using :include seems to trigger an erroneous eager load of 
    # observations that screws up sorting kueda 2011-07-22
    joins(:project_observations).where("project_observations.project_id IN (?)", Project.slugs_to_ids(projects))
  }
  
  scope :on, lambda {|date| where(Observation.conditions_for_date(:observed_on, date)) }
  
  scope :created_on, lambda {|date| where(Observation.conditions_for_date("observations.created_at", date))}
  
  scope :out_of_range, -> { where(:out_of_range => true) }
  scope :in_range, -> { where(:out_of_range => false) }
  scope :license, lambda {|license|
    if license == 'none'
      where("observations.license IS NULL")
    elsif LICENSE_CODES.include?(license)
      where(:license => license)
    else
      where("observations.license IS NOT NULL")
    end
  }
  
  scope :photo_license, lambda {|license|
    license = license.to_s
    scope = joins(:photos)
    license_number = Photo.license_number_for_code(license)
    if license == 'none'
      scope.where("photos.license = 0")
    elsif LICENSE_CODES.include?(license)
      scope.where("photos.license = ?", license_number)
    else
      scope.where("photos.license > 0")
    end
  }

  scope :has_observation_field, lambda{|*args|
    field, value = args
    join_name = "ofv_#{field.is_a?(ObservationField) ? field.id : field}"
    scope = joins("LEFT OUTER JOIN observation_field_values #{join_name} ON #{join_name}.observation_id = observations.id").
      where("#{join_name}.observation_field_id = ?", field)
    scope = scope.where("#{join_name}.value = ?", value) unless value.blank?
    scope
  }

  scope :between_hours, lambda{|h1, h2|
    h1 = h1.to_i % 24
    h2 = h2.to_i % 24
    where("EXTRACT(hour FROM ((time_observed_at AT TIME ZONE 'GMT') AT TIME ZONE zic_time_zone)) BETWEEN ? AND ?", h1, h2)
  }

  scope :between_months, lambda{|m1, m2|
    m1 = m1.to_i % 12
    m2 = m2.to_i % 12
    if m1 > m2
      where("EXTRACT(month FROM observed_on) >= ? OR EXTRACT(month FROM observed_on) <= ?", m1, m2)
    else
      where("EXTRACT(month FROM observed_on) BETWEEN ? AND ?", m1, m2)
    end
  }

  scope :between_dates, lambda{|d1, d2|
    t1 = (Time.parse(URI.unescape(d1.to_s)) rescue Time.now)
    t2 = (Time.parse(URI.unescape(d2.to_s)) rescue Time.now)
    if d1.to_s.index(':')
      where("time_observed_at BETWEEN ? AND ? OR (time_observed_at IS NULL AND observed_on BETWEEN ? AND ?)", t1, t2, t1.to_date, t2.to_date)
    else
      where("observed_on BETWEEN ? AND ?", t1, t2)
    end
  }

  scope :dbsearch, lambda {|*args|
    q, on = args
    q = sanitize_query(q) unless q.blank?
    case on
    when 'species_guess'
      where("observations.species_guess ILIKE", "%#{q}%")
    when 'description'
      where("observations.description ILIKE", "%#{q}%")
    when 'place_guess'
      where("observations.place_guess ILIKE", "%#{q}%")
    when 'tags'
      where("observations.cached_tag_list ILIKE", "%#{q}%")
    else
      where("observations.species_guess ILIKE ? OR observations.description ILIKE ? OR observations.cached_tag_list ILIKE ? OR observations.place_guess ILIKE ?", 
        "%#{q}%", "%#{q}%", "%#{q}%", "%#{q}%")
    end
  }
  
  scope :reviewed_by, lambda { |users|
    joins(:observation_reviews).where("observation_reviews.user_id IN (?)", users)
  }
  scope :not_reviewed_by, lambda { |users|
    users = [ users ] unless users.is_a?(Array)
    user_ids = users.map{ |u| ElasticModel.id_or_object(u) }
    joins("LEFT JOIN observation_reviews ON (observations.id=observation_reviews.observation_id)
      AND observation_reviews.user_id IN (#{ user_ids.join(',') })").
      where("observation_reviews.id IS NULL")
  }

  def self.near_place(place)
    place = (Place.find(place) rescue nil) unless place.is_a?(Place)
    if place.swlat
      Observation.in_bounding_box(place.swlat, place.swlng, place.nelat, place.nelng)
    else
      Observation.near_point(place.latitude, place.longitude)
    end
  end

  def self.preload_for_component(observations, logged_in)
    preloads = [
      { user: :stored_preferences },
      { taxon: { taxon_names: :place_taxon_names } },
      :iconic_taxon,
      { photos: [ :flags, :user ] },
      :stored_preferences, :flags, :quality_metrics ]
    # why do we need taxon_descriptions when logged in?
    if logged_in
      preloads.delete(:iconic_taxon)
      preloads << { iconic_taxon: :taxon_descriptions }
      preloads << :project_observations
    end
    Observation.preload_associations(observations, preloads)
  end

  # help_txt_for :species_guess, <<-DESC
  #   Type a name for what you saw.  It can be common or scientific, accurate 
  #   or just a placeholder. When you enter it, we'll try to look it up and find
  #   the matching species of higher level taxon.
  # DESC
  # 
  # instruction_for :place_guess, "Type the name of a place"
  # help_txt_for :place_guess, <<-DESC
  #   Enter the name of a place and we'll try to find where it is. If we find
  #   it, you can drag the map marker around to get more specific.
  # DESC
  
  def to_s
    "<Observation #{self.id}: #{to_plain_s}>"
  end
  
  def to_plain_s(options = {})
    s = self.species_guess.blank? ? I18n.t(:something) : self.species_guess
    if options[:verb]
      s += options[:verb] == true ? I18n.t(:observed).downcase : " #{options[:verb]}"
    end
    unless self.place_guess.blank? || options[:no_place_guess] || coordinates_obscured?
      s += " #{I18n.t(:from, :default => 'from').downcase} #{self.place_guess}"
    end
    s += " #{I18n.t(:on_day)}  #{I18n.l(self.observed_on, :format => :long)}" unless self.observed_on.blank?
    unless self.time_observed_at.blank? || options[:no_time]
      s += " #{I18n.t(:at)} #{self.time_observed_at_in_zone.to_s(:plain_time)}"
    end
    s += " #{I18n.t(:by).downcase} #{user.try_methods(:name, :login)}" unless options[:no_user]
    s.gsub(/\s+/, ' ')
  end
  
  def time_observed_at_utc
    time_observed_at.try(:utc)
  end
  
  def serializable_hash(opts = nil)
    # for some reason, in some cases options was still nil
    options = opts ? opts.clone : { }
    # making a deep copy of the options so they don't get modified
    # This was more effective than options.deep_dup
    if options[:include] && (options[:include].is_a?(Hash) || options[:include].is_a?(Array))
      options[:include] = options[:include].marshal_copy
    end
    # don't use delete here, it will just remove the option for all 
    # subsequent records in an array
    options[:include] = if options[:include].is_a?(Hash)
      options[:include].map{|k,v| {k => v}}
    else
      [options[:include]].flatten.compact
    end
    options[:methods] ||= []
    options[:methods] += [:created_at_utc, :updated_at_utc,
      :time_observed_at_utc, :faves_count, :owners_identification_from_vision]
    viewer = options[:viewer]
    viewer_id = viewer.is_a?(User) ? viewer.id : viewer.to_i
    options[:except] ||= []
    options[:except] += [:user_agent]
    if viewer_id != user_id && !options[:force_coordinate_visibility]
      options[:except] += [:private_latitude, :private_longitude,
        :private_positional_accuracy, :geom, :private_geom, :private_place_guess]
      options[:methods] << :coordinates_obscured
    end
    options[:except] += [:cached_tag_list, :geom, :private_geom]
    options[:except].uniq!
    options[:methods].uniq!
    h = super(options)
    h.each do |k,v|
      h[k] = v.gsub(/<script.*script>/i, "") if v.is_a?(String)
    end
    h.force_utf8
  end
  
  #
  # Return a time from observed_on and time_observed_at
  #
  def datetime
    @datetime ||= if observed_on && errors[:observed_on].blank?
      time_observed_at_in_zone ||
      Time.new(observed_on.year,
               observed_on.month,
               observed_on.day, 0, 0, 0,
               timezone_offset)
    end
  end

  def timezone_object
    # returns nil if the time_zone has an invalid value
    (time_zone && ActiveSupport::TimeZone.new(time_zone)) ||
      (zic_time_zone && ActiveSupport::TimeZone.new(zic_time_zone))
  end

  def timezone_offset
    # returns nil if the time_zone has an invalid value
    (timezone_object || ActiveSupport::TimeZone.new("UTC")).formatted_offset
  end

  # Return time_observed_at in the observation's time zone
  def time_observed_at_in_zone
    if self.time_observed_at
      self.time_observed_at.in_time_zone(self.time_zone)
    end
  end
  
  #
  # Set all the time fields based on the contents of observed_on_string
  #
  def munge_observed_on_with_chronic
    if observed_on_string.blank?
      self.observed_on = nil
      self.time_observed_at = nil
      return true
    end
    date_string = observed_on_string.strip
    tz_abbrev_pattern = /\s\(?([A-Z]{3,})\)?$/ # ends with (PDT)
    tz_offset_pattern = /([+-]\d{4})$/ # contains -0800
    tz_js_offset_pattern = /(GMT)?([+-]\d{4})/ # contains GMT-0800
    tz_colon_offset_pattern = /(GMT|HSP)([+-]\d+:\d+)/ # contains (GMT-08:00)
    tz_failed_abbrev_pattern = /\(#{tz_colon_offset_pattern}\)/
    
    if date_string =~ /#{tz_js_offset_pattern} #{tz_failed_abbrev_pattern}/
      date_string = date_string.sub(tz_failed_abbrev_pattern, '').strip
    end

    # Rails timezone support doesn't seem to recognize this abbreviation, and
    # frankly I have no idea where ActiveSupport::TimeZone::CODES comes from.
    # In case that ever stops working or a less hackish solution is required,
    # check out https://gist.github.com/kueda/3e6f77f64f792b4f119f
    tz_abbrev = date_string[tz_abbrev_pattern, 1]
    tz_abbrev = 'CET' if tz_abbrev == 'CEST'
    
    if parsed_time_zone = ActiveSupport::TimeZone::CODES[tz_abbrev]
      date_string = observed_on_string.sub(tz_abbrev_pattern, '')
      date_string = date_string.sub(tz_js_offset_pattern, '').strip
      self.time_zone = parsed_time_zone.name if observed_on_string_changed?
    elsif (offset = date_string[tz_offset_pattern, 1]) && 
        (n = offset.to_f / 100) && 
        (key = n == 0 ? 0 : n.floor + (n%n.floor)/0.6) && 
        (parsed_time_zone = ActiveSupport::TimeZone[key])
      date_string = date_string.sub(tz_offset_pattern, '')
      self.time_zone = parsed_time_zone.name if observed_on_string_changed?
    elsif (offset = date_string[tz_js_offset_pattern, 2]) && 
        (n = offset.to_f / 100) && 
        (key = n == 0 ? 0 : n.floor + (n%n.floor)/0.6) && 
        (parsed_time_zone = ActiveSupport::TimeZone[key])
      date_string = date_string.sub(tz_js_offset_pattern, '')
      date_string = date_string.sub(/^(Sun|Mon|Tue|Wed|Thu|Fri|Sat)\s+/i, '')
      self.time_zone = parsed_time_zone.name if observed_on_string_changed?
    elsif (offset = date_string[tz_colon_offset_pattern, 2]) && 
        (t = Time.parse(offset)) && 
        (parsed_time_zone = ActiveSupport::TimeZone[t.hour+t.min/60.0])
      date_string = date_string.sub(/#{tz_colon_offset_pattern}|#{tz_failed_abbrev_pattern}/, '')
      self.time_zone = parsed_time_zone.name if observed_on_string_changed?
    end
    
    date_string.sub!('T', ' ') if date_string =~ /\d{4}-\d{2}-\d{2}T/
    date_string.sub!(/(\d{2}:\d{2}:\d{2})\.\d+/, '\\1')
    
    # strip leading month if present
    date_string.sub!(/^[A-z]{3} ([A-z]{3})/, '\\1')

    # strip paranthesized stuff
    date_string.gsub!(/\(.*\)/, '')

    # strip noon hour madness
    # this is due to a weird, weird bug in Chronic
    if date_string =~ /p\.?m\.?/i
      date_string.gsub!( /( 12:(\d\d)(:\d\d)?)\s+?p\.?m\.?/i, '\\1')
    elsif date_string =~ /a\.?m\.?/i
      date_string.gsub!( /( 12:(\d\d)(:\d\d)?)\s+?a\.?m\.?/i, '\\1')
      date_string.gsub!( / 12:/, " 00:" )
    end
    
    # Set the time zone appropriately
    old_time_zone = Time.zone
    begin
      Time.zone = time_zone || user.try(:time_zone)
    rescue ArgumentError
      # Usually this would happen b/c of an invalid time zone being specified
      self.time_zone = time_zone_was || old_time_zone.name
    end
    Chronic.time_class = Time.zone
    
    begin
      # Start parsing...
      t = begin
        Chronic.parse(date_string)
      rescue ArgumentError
        nil
      end
      t = Chronic.parse(date_string.split[0..-2].join(' ')) unless t 
      if !t && (locale = user.locale || I18n.locale)
        date_string = englishize_month_abbrevs_for_locale(date_string, locale)
        t = Chronic.parse(date_string)
      end

      if !t
        I18N_SUPPORTED_LOCALES.each do |locale|
          next if locale =~ /^en.*/
          new_date_string = englishize_month_abbrevs_for_locale(date_string, locale)
          break if t = Chronic.parse(new_date_string)
        end
      end
      return true unless t
    
      # Re-interpret future dates as being in the past
      t = Chronic.parse(date_string, :context => :past) if t > Time.now
      
      self.observed_on = t.to_date if t
    
      # try to determine if the user specified a time by ask Chronic to return
      # a time range. Time ranges less than a day probably specified a time.
      if tspan = Chronic.parse(date_string, :context => :past, :guess => false)
        # If tspan is less than a day and the string wasn't 'today', set time
        if tspan.width < 86400 && date_string.strip.downcase != 'today'
          self.time_observed_at = t
        else
          self.time_observed_at = nil
        end
      end
    rescue RuntimeError, ArgumentError
      # ignore these, just don't set the date
      return true
    end
    
    # don't store relative observed_on_strings, or they will change
    # every time you save an observation!
    if date_string =~ /today|yesterday|ago|last|this|now|monday|tuesday|wednesday|thursday|friday|saturday|sunday/i
      self.observed_on_string = self.observed_on.to_s
      if self.time_observed_at
        self.observed_on_string = self.time_observed_at.strftime("%Y-%m-%d %H:%M:%S")
      end
    end
    
    # Set the time zone back the way it was
    Time.zone = old_time_zone
    true
  end

  def englishize_month_abbrevs_for_locale(date_string, locale)
    # HACK attempt to translate month abbreviations into English. 
    # A much better approach would be add Spanish and any other supported
    # locales to https://github.com/olojac/chronic-l10n and switch to the
    # 'localized' branch of Chronic, which seems to clear our test suite.
    return date_string if locale.to_s =~ /^en/
    return date_string unless I18N_SUPPORTED_LOCALES.include?(locale)
    I18n.t('date.abbr_month_names', :locale => :en).each_with_index do |en_month_name,i|
      next if i == 0
      localized_month_name = I18n.t('date.abbr_month_names', :locale => locale)[i]
      next if localized_month_name == en_month_name
      date_string.gsub!(/#{localized_month_name}([\s\,])/, "#{en_month_name}\\1")
    end
    date_string
  end
  
  #
  # Adds, updates, or destroys the identification corresponding to the taxon
  # the user selected.
  #
  def update_identifications
    return true if @skip_identifications
    return true unless taxon_id_changed?
    owners_ident = identifications.where( user_id: user_id ).order( "id asc" ).last
    
    # If there's a taxon we need to make sure the owner's ident agrees
    if taxon && ( owners_ident.blank? || owners_ident.taxon_id != taxon.id )
      # If the owner doesn't have an identification for this obs, make one
      attrs = {
        user: user,
        taxon: taxon,
        observation: self,
        skip_observation: true,
        vision: owners_identification_from_vision_requested
      }
      owners_ident = if new_record?
        self.identifications.build( attrs )
      else
        self.identifications.create( attrs )
      end
    elsif taxon.blank? && owners_ident && owners_ident.current?
      if identifications.where( user_id: user_id ).count > 1
        owners_ident.update_attributes( current: false, skip_observation: true )
      else
        owners_ident.skip_observation = true
        owners_ident.destroy
      end
    end
    
    update_stats( skip_save: true )
    
    true
  end

  # Override nested obs field values attributes setter to ensure that field
  # values get added even if existing field values have been destroyed (e.g.
  # two windows). Also updating existing OFV of same OF name if id not 
  # specified
  def observation_field_values_attributes=(attributes)
    attr_array = attributes.is_a?(Hash) ? attributes.values : attributes
    return unless attr_array
    attr_array.each_with_index do |v,i|
      if v["id"].blank?
        existing = observation_field_values.where(:observation_field_id => v["observation_field_id"]).first unless v["observation_field_id"].blank?
        existing ||= observation_field_values.joins(:observation_fields).where("lower(observation_fields.name) = ?", v["name"]).first unless v["name"].blank?
        attr_array[i]["id"] = existing.id if existing
      elsif !ObservationFieldValue.where("id = ?", v["id"]).exists?
        attr_array[i].delete("id")
      end
    end
    assign_nested_attributes_for_collection_association(:observation_field_values, attr_array)
  end
  
  #
  # Update the user's lists with changes to this observation's taxon
  #
  # If the observation is the last_observation in any of the user's lists,
  # then the last_observation should be reset to another observation.
  #
  def refresh_lists
    return true if skip_refresh_lists
    return true unless taxon_id_changed? || quality_grade_changed?
    
    # Update the observation's current taxon and/or a previous one that was
    # just removed/changed
    target_taxa = [
      taxon, 
      Taxon.find_by_id(@old_observation_taxon_id)
    ].compact.uniq
    # Don't refresh all the lists if nothing changed
    return true if target_taxa.empty?
    
    # Refreh the ProjectLists
    ProjectList.delay(priority: USER_INTEGRITY_PRIORITY, queue: "slow",
      unique_hash: { "ProjectList::refresh_with_observation": id }).
      refresh_with_observation(id, :taxon_id => taxon_id,
        :taxon_id_was => taxon_id_was, :user_id => user_id, :created_at => created_at)

    # Don't refresh LifeLists and Lists if only quality grade has changed
    return true unless taxon_id_changed?
    List.delay(priority: USER_INTEGRITY_PRIORITY, queue: "slow",
      unique_hash: { "List::refresh_with_observation": id }).
      refresh_with_observation(id, :taxon_id => taxon_id,
        :taxon_id_was => taxon_id_was, :user_id => user_id, :created_at => created_at,
        :skip_subclasses => true)
    LifeList.delay(priority: USER_INTEGRITY_PRIORITY, queue: "slow",
      unique_hash: { "LifeList::refresh_with_observation": id }).
      refresh_with_observation(id, :taxon_id => taxon_id,
        :taxon_id_was => taxon_id_was, :user_id => user_id, :created_at => created_at)

    # Reset the instance var so it doesn't linger around
    @old_observation_taxon_id = nil
    true
  end
  
  def refresh_check_lists
    return true if skip_refresh_check_lists
    refresh_needed = (georeferenced? || was_georeferenced?) && 
      (taxon_id || taxon_id_was) && 
      (quality_grade_changed? || taxon_id_changed? || latitude_changed? || longitude_changed? || observed_on_changed?)
    return true unless refresh_needed
    CheckList.delay(priority: INTEGRITY_PRIORITY, queue: "slow",
      unique_hash: { "CheckList::refresh_with_observation": id }).
      refresh_with_observation(id, :taxon_id => taxon_id,
        :taxon_id_was  => taxon_id_changed? ? taxon_id_was : nil,
        :latitude_was  => (latitude_changed? || longitude_changed?) ? latitude_was : nil,
        :longitude_was => (latitude_changed? || longitude_changed?) ? longitude_was : nil,
        :new => id_was.blank?)
    true
  end
  
  # Because it has to be slightly different, in that the taxon of a destroyed
  # obs shouldn't be removed by default from life lists (maybe you've seen it
  # in the past, but you don't have any other obs), but those listed_taxa of
  # this taxon should have their last_observation reset.
  #
  def refresh_lists_after_destroy
    return true if skip_refresh_lists
    return true unless taxon
    List.delay(:priority => USER_INTEGRITY_PRIORITY).refresh_with_observation(id, :taxon_id => taxon_id, 
      :taxon_id_was => taxon_id_was, :user_id => user_id, :created_at => created_at,
      :skip_subclasses => true)
    LifeList.delay(:priority => USER_INTEGRITY_PRIORITY).refresh_with_observation(id, :taxon_id => taxon_id, 
      :taxon_id_was => taxon_id_was, :user_id => user_id, :created_at => created_at)
    true
  end
  
  #
  # Preserve the old taxon id if the taxon has changed so we know to update
  # that taxon in the user's lists after_save
  #
  def keep_old_taxon_id
    @old_observation_taxon_id = taxon_id_was if taxon_id_changed?
    true
  end
  
  #
  # Set the iconic taxon if it hasn't been set
  #
  def set_iconic_taxon
    if taxon
      self.iconic_taxon_id ||= taxon.iconic_taxon_id
    else
      self.iconic_taxon_id = nil
    end
    true
  end

  def replace_inactive_taxon
    return true if taxon.blank? || ( taxon && taxon.is_active? )
    return true unless candidate = taxon.current_synonymous_taxon
    self.taxon = candidate
    true
  end

  #
  # Trim whitespace around species guess
  #
  def strip_species_guess
    self.species_guess.to_s.strip! unless species_guess.blank?
    true
  end
  
  #
  # Set the time_zone of this observation if not already set
  #
  def set_time_zone
    self.time_zone = nil if time_zone.blank?
    self.time_zone ||= user.time_zone if user && !user.time_zone.blank?
    self.time_zone ||= Time.zone.try(:name) unless time_observed_at.blank?
    self.time_zone ||= 'UTC'
    self.zic_time_zone = ActiveSupport::TimeZone::MAPPING[time_zone] unless time_zone.blank?
    true
  end
  
  #
  # Force time_observed_at into the time zone
  #
  def set_time_in_time_zone
    return true if time_observed_at.blank? || time_zone.blank?
    return true unless time_observed_at_changed? || time_zone_changed?
    
    # Render the time as a string
    time_s = time_observed_at_before_type_cast
    unless time_s.is_a? String
      time_s = time_observed_at_before_type_cast.strftime("%Y-%m-%d %H:%M:%S")
    end
    
    # Get the time zone offset as a string and append it
    offset_s = Time.parse(time_s).in_time_zone(time_zone).formatted_offset(false)
    time_s += " #{offset_s}"
    
    self.time_observed_at = Time.parse(time_s)
    true
  end
  
  def set_captive
    update_column(:captive, captive_cultivated)
  end

  def component_cache_key(options = {})
    Observation.component_cache_key(id, options)
  end
  
  def self.component_cache_key(id, options = {})
    key = "obs_comp_#{id}"
    key += "_"+options.sort.map{|k,v| "#{k}-#{v}"}.join('_') unless options.blank?
    key
  end
  
  def num_identifications_by_others
    num_identification_agreements + num_identification_disagreements
  end
  
  def appropriate?
    return false if flagged?
    return false if observation_photos_count > 0 && photos.detect{ |p| p.flagged? }
    true
  end
  
  def georeferenced?
    (!latitude.nil? && !longitude.nil?) || (!private_latitude.nil? && !private_longitude.nil?)
  end
  
  def was_georeferenced?
    (latitude_was && longitude_was) || (private_latitude_was && private_longitude_was)
  end
  
  def quality_metric_score(metric)
    quality_metrics.all unless quality_metrics.loaded?
    metrics = quality_metrics.select{|qm| !qm.frozen? && qm.metric == metric}
    return nil if metrics.blank?
    metrics.select{|qm| qm.agree?}.size.to_f / metrics.size
  end
  
  def community_supported_id?
    if community_taxon_rejected?
      num_identification_agreements.to_i > 0 && num_identification_agreements > num_identification_disagreements
    else
      !community_taxon_id.blank? && taxon_id == community_taxon_id
    end
  end
  
  def quality_metrics_pass?
    QualityMetric::METRICS.each do |metric|
      return false unless passes_quality_metric?(metric)
    end
    true
  end

  def passes_quality_metric?(metric)
    score = quality_metric_score(metric)
    score.blank? || score >= 0.5
  end

  def research_grade_candidate?
    return false if human?
    return false unless georeferenced?
    return false unless quality_metrics_pass?
    return false unless observed_on?
    return false unless (photos? || sounds?)
    return false unless appropriate?
    true
  end
  
  def human?
    t = community_taxon || taxon
    t && ( t.name =~ /^Homo / || t.name == "Homo" )
  end
  
  def research_grade?
    quality_grade == RESEARCH_GRADE
  end

  def verifiable?
    [ NEEDS_ID, RESEARCH_GRADE ].include?(quality_grade)
  end

  def photos?
    # new observations from the uploader may have .photos
    # but may not yet have observation_p
    return true if photos && photos.any?
    observation_photos.loaded? ? ! observation_photos.empty? : observation_photos.exists?
  end

  def sounds?
    sounds.loaded? ? ! sounds.empty? : sounds.exists?
  end
  
  def set_quality_grade(options = {})
    self.quality_grade = get_quality_grade
    true
  end
  
  def self.set_quality_grade(id)
    return unless observation = Observation.find_by_id(id)
    observation.set_quality_grade(:force => true)
    observation.save
    if observation.quality_grade_changed?
      CheckList.delay(priority: INTEGRITY_PRIORITY, queue: "slow",
        unique_hash: { "CheckList::refresh_with_observation": id }).
        refresh_with_observation(observation.id, :taxon_id => observation.taxon_id)
    end
    observation.quality_grade
  end
  
  def get_quality_grade
    if !research_grade_candidate?
      CASUAL
    elsif voted_in_to_needs_id?
      NEEDS_ID
    elsif community_taxon_id && community_taxon_rejected?
      if owners_identification.blank? || owners_identification.maverick?
        CASUAL
      elsif (
        owners_identification &&
        owners_identification.taxon.rank_level &&
        owners_identification.taxon.rank_level <= Taxon::SPECIES_LEVEL &&
        community_taxon.self_and_ancestor_ids.include?( owners_identification.taxon.id )
      )
        RESEARCH_GRADE
      else
        NEEDS_ID
      end
    elsif community_taxon_at_species_or_lower?
      RESEARCH_GRADE
    elsif community_taxon_id && voted_out_of_needs_id?
      if community_taxon_below_family?
        RESEARCH_GRADE
      else
        CASUAL
      end
    else
      NEEDS_ID
    end
  end
  
  def coordinates_obscured?
    !private_latitude.blank? || !private_longitude.blank?
  end
  alias :coordinates_obscured :coordinates_obscured?

  def coordinates_private?
    latitude.blank? && longitude.blank? && private_latitude? && private_longitude?
  end

  def coordinates_changed?
    latitude_changed? || longitude_changed? || private_latitude_changed? || private_longitude_changed?
  end
  
  def geoprivacy_private?
    geoprivacy == PRIVATE
  end
  
  def geoprivacy_obscured?
    geoprivacy == OBSCURED
  end
  
  def coordinates_viewable_by?(viewer)
    return true unless coordinates_obscured?
    return false if viewer.blank?
    viewer = User.find_by_id(viewer) unless viewer.is_a?(User)
    return false unless viewer
    return true if user_id == viewer.id
    project_ids = if projects.loaded?
      projects.map(&:id)
    else
      project_observations.map(&:project_id)
    end
    viewer.project_users.select{|pu| project_ids.include?(pu.project_id) && ProjectUser::ROLES.include?(pu.role)}.each do |pu|
      if project_observations.detect{|po| po.project_id == pu.project_id && po.prefers_curator_coordinate_access?}
        return true
      end
    end
    false
  end
  
  def reset_private_coordinates_if_coordinates_changed
    if (latitude_changed? || longitude_changed?)
      self.private_latitude = nil
      self.private_longitude = nil
    end
    true
  end

  def normalize_geoprivacy
    self.geoprivacy = nil unless GEOPRIVACIES.include?(geoprivacy)
    true
  end
  
  def obscure_coordinates_for_geoprivacy
    self.geoprivacy = nil if geoprivacy.blank?
    return true if geoprivacy.blank? && !geoprivacy_changed?
    case geoprivacy
    when PRIVATE
      obscure_coordinates unless coordinates_obscured?
      self.latitude, self.longitude = [nil, nil]
    when OBSCURED
      obscure_coordinates unless coordinates_obscured?
    else
      unobscure_coordinates
    end
    true
  end
  
  def obscure_coordinates_for_threatened_taxa
    lat = private_latitude.blank? ? latitude : private_latitude
    lon = private_longitude.blank? ? longitude : private_longitude
    t = taxon || community_taxon
    target_taxon_ids = [[t.try(:id)] + identifications.current.pluck(:taxon_id)].flatten.compact.uniq
    taxon_geoprivacy = Taxon.max_geoprivacy( target_taxon_ids, latitude: lat, longitude: lon )
    case taxon_geoprivacy
    when OBSCURED
      obscure_coordinates unless coordinates_obscured?
    when PRIVATE
      unless coordinates_private?
        obscure_coordinates
        self.latitude, self.longitude = [nil, nil]
      end
    else
      unobscure_coordinates
    end
    true
  end
  
  def obscure_coordinates
    return if latitude.blank? || longitude.blank?
    if latitude_changed? || longitude_changed?
      self.private_latitude = latitude
      self.private_longitude = longitude
    else
      self.private_latitude ||= latitude
      self.private_longitude ||= longitude
    end
    self.latitude, self.longitude = Observation.random_neighbor_lat_lon( private_latitude, private_longitude )
    set_geom_from_latlon
    true
  end


  def obscure_place_guess
    public_place_guess = Observation.place_guess_from_latlon(
      private_latitude,
      private_longitude,
      acc: calculate_public_positional_accuracy,
      user: user
    )
    if coordinates_private?
      if place_guess_changed? && place_guess == private_place_guess
        self.place_guess = nil
      elsif !place_guess.blank? && place_guess != public_place_guess
        self.private_place_guess = place_guess
        self.place_guess = nil
      end
    elsif coordinates_obscured?
      if place_guess_changed?
        if place_guess == private_place_guess
          self.place_guess = public_place_guess
        else
          self.private_place_guess = place_guess
          self.place_guess = public_place_guess
        end
      elsif private_latitude_changed? && private_place_guess.blank?
        self.private_place_guess = place_guess
        self.place_guess = public_place_guess
      end
    else
      unless place_guess_changed? || private_place_guess.blank?
        self.place_guess = private_place_guess
      end
      self.private_place_guess = nil
    end
    true
  end
  
  def lat_lon_in_place_guess?
    !place_guess.blank? && place_guess !~ /[a-cf-mo-rt-vx-z]/i && !place_guess.scan(COORDINATE_REGEX).blank?
  end
  
  def unobscure_coordinates
    return unless coordinates_obscured? || coordinates_private?
    return unless geoprivacy.blank?
    self.latitude = private_latitude
    self.longitude = private_longitude
    self.private_latitude = nil
    self.private_longitude = nil
    set_geom_from_latlon
  end
  
  def iconic_taxon_name
    return nil if iconic_taxon_id.blank?
    if Taxon::ICONIC_TAXA_BY_ID.blank?
      association(:iconic_taxon).loaded? ? iconic_taxon.try(:name) : Taxon.select("id, name").where(:id => iconic_taxon_id).first.try(:name)
    else
      Taxon::ICONIC_TAXA_BY_ID[iconic_taxon_id].try(:name)
    end
  end

  def captive_cultivated?
    !passes_quality_metric?(QualityMetric::WILD)
  end
  alias :captive_cultivated :captive_cultivated?

  def reviewed_by?(viewer)
    viewer = User.find_by_id(viewer) unless viewer.is_a?(User)
    return false unless viewer
    ObservationReview.where(observation_id: id,
      user_id: viewer.id, reviewed: true).exists?
  end

  ##### Community Taxon #########################################################

  def get_community_taxon(options = {})
    return if (
      identifications.loaded? ?
      identifications.select(&:current?).select(&:persisted?).uniq :
      identifications.current
    ).count <= 1
    nodes = community_taxon_nodes(options)
    node = nodes.select{|n| n[:cumulative_count] > 1}.sort_by do |n|
      [
        n[:score].to_f > COMMUNITY_TAXON_SCORE_CUTOFF ? 1 : 0, # only consider taxa with a score above the cutoff
        0 - (n[:taxon].rank_level || 500) # within that set, sort by rank level, i.e. choose lowest rank
      ]
    end.last
    
    # # Visualizing this stuff is pretty useful for testing, so please leave this in
    # print_community_taxon_nodes( nodes )
    return unless node
    node[:taxon]
  end

  def print_community_taxon_nodes( nodes = nil )
    nodes ||= community_taxon_nodes
    puts
    width = 15
    %w(taxon_id taxon_name cc dc cdc score).each do |c|
      if c == "taxon_name"
        print c.ljust( width*2 )
      else
        print c.ljust( width )
      end
    end
    puts
    nodes.sort_by{|n| n[:taxon].ancestry || ""}.each do |n|
      print n[:taxon].id.to_s.ljust(width)
      print n[:taxon].name.to_s.ljust(width*2)
      print n[:cumulative_count].to_s.ljust(width)
      print n[:disagreement_count].to_s.ljust(width)
      print n[:conservative_disagreement_count].to_s.ljust(width)
      print n[:score].to_s.ljust(width)
      puts
    end
  end

  def community_taxon_nodes( options = {} )
    return @community_taxon_nodes if @community_taxon_nodes && !options[:force]
    # work on current identifications
    ids = identifications.loaded? ?
      identifications.select(&:current?).select(&:persisted?).uniq :
      identifications.current.includes(:taxon)
    working_idents = ids.select{|i| i.taxon.is_active }.sort_by(&:id)
    if options[:before].to_i > 0
      working_idents = working_idents.select{|i| i.id < options[:before].to_i }
    elsif options[:before].is_a?( DateTime ) || options[:before].is_a?( ActiveSupport::TimeWithZone )
      working_idents = working_idents.select{|i| i.created_at < options[:before] }
    end

    # load all ancestor taxa implied by identifications
    ancestor_ids = working_idents.map{|i| i.taxon.ancestor_ids}.flatten.uniq.compact
    taxon_ids = working_idents.map{|i| [i.taxon_id] + i.taxon.ancestor_ids}.flatten.uniq.compact
    taxa = Taxon.where("id IN (?)", taxon_ids)
    taxon_ids_count = taxon_ids.size

    @community_taxon_nodes = taxa.map do |id_taxon|
      # puts id_taxon.name
      # count all identifications of this taxon and its descendants
      cumulative_count = working_idents.select{|i| i.taxon.self_and_ancestor_ids.include?(id_taxon.id)}.size

      # count identifications of taxa that are outside of this taxon's subtree
      # (i.e. absolute disagreements)
      disagreement_count = working_idents.reject{|i|
       id_taxon.self_and_ancestor_ids.include?(i.taxon_id) || i.taxon.self_and_ancestor_ids.include?(id_taxon.id)
      }.size

      # Count identifications that explicitly disagreed with an ancestor of this taxon
      first_ident_of_taxon = working_idents.detect{|i| i.taxon.self_and_ancestor_ids.include?(id_taxon.id)}
      conservative_disagreement_count = if first_ident_of_taxon
        working_idents.select {|i|
          # puts "\tID #{i.id}: #{i.taxon.name}"
          # puts "\t\ti.disagreement?: #{i.disagreement?}"
          # puts "\t\ti.previous_observation_taxon: #{i.previous_observation_taxon}"
          if (
            i.disagreement? &&
            i.previous_observation_taxon &&
            ( base_index = i.previous_observation_taxon.ancestor_ids.index( i.taxon_id ) )
          )

            # If an identification of Homonidae is a disagreement with Homo
            # sapiens, that implies disagreement with everything between
            # Homonidae and Homo sapiens (i.e. genus Homo), otherwise they would
            # have added an ID of genus Homo
            disagreement_branch_taxon_ids = i.previous_observation_taxon.self_and_ancestor_ids[base_index+1..-1]
            # puts "\t\tdisagreement_branch_taxon_ids: #{disagreement_branch_taxon_ids}"
            # So if the taxon under consideration is any of the taxa this
            # identification disagrees with, count it as a disagreement
            # puts "\t\t( id_taxon.self_and_ancestor_ids & disagreement_branch_taxon_ids ): #{( id_taxon.self_and_ancestor_ids & disagreement_branch_taxon_ids )}"
            ( id_taxon.self_and_ancestor_ids & disagreement_branch_taxon_ids ).size > 0
          elsif i.disagreement == nil
            i.id > first_ident_of_taxon.id && id_taxon.ancestor_ids.include?( i.taxon_id )
          end
        }.size
      else
        0
      end

      {
        taxon: id_taxon,
        ident_count: working_idents.select{|i| i.taxon_id == id_taxon.id}.size,
        cumulative_count: cumulative_count,
        disagreement_count: disagreement_count,
        conservative_disagreement_count: conservative_disagreement_count,
        score: cumulative_count.to_f / (cumulative_count + disagreement_count + conservative_disagreement_count)
      }
    end
  end

  def set_community_taxon(options = {})
    community_taxon = get_community_taxon(options)
    self.community_taxon = community_taxon
    if self.changed? && !community_taxon.nil? && !community_taxon_rejected?
      self.species_guess = (community_taxon.common_name.try(:name) || community_taxon.name)
    end
    true
  end

  def set_community_taxon_before_save
    set_community_taxon(:force => true) if prefers_community_taxon_changed? || taxon_id_changed?
    true
  end

  def self.set_community_taxa(options = {})
    scope = Observation.includes({:identifications => [:taxon]}, :user)
    scope = scope.where(options[:where]) if options[:where]
    scope = scope.by(options[:user]) unless options[:user].blank?
    scope = scope.of(options[:taxon]) unless options[:taxon].blank?
    scope = scope.in_place(options[:place]) unless options[:place].blank?
    scope = scope.in_projects([options[:project]]) unless options[:project].blank?
    start_time = Time.now
    logger = options[:logger] || Rails.logger
    logger.info "[INFO #{Time.now}] Starting Observation.set_community_taxon, options: #{options.inspect}"
    scope.find_each do |o|
      next unless o.identifications.size > 1
      o.set_community_taxon
      unless o.save
        logger.error "[ERROR #{Time.now}] Failed to set community taxon for #{o}: #{o.errors.full_messages.to_sentence}"
      end
    end
    logger.info "[INFO #{Time.now}] Finished Observation.set_community_taxon in #{Time.now - start_time}s, options: #{options.inspect}"
  end

  def community_taxon_rejected?
    return false if prefers_community_taxon == true
    (prefers_community_taxon == false || user.prefers_community_taxa == false)
  end

  # What the system thinks the organism probably is. Current combines the
  # communal opinion with the preferences of individuals (disagreement / not
  # disagreement), and may in the future incorporate modeled identifier skill
  def probable_taxon( options = {} )
    nodes = community_taxon_nodes( options )
    node = nodes.select{|n| n[:score].to_f > COMMUNITY_TAXON_SCORE_CUTOFF }.sort_by {|n|
      0 - (n[:taxon].rank_level || 500) # within that set, sort by rank level, i.e. choose lowest rank
    }.last
    return unless node
    node[:taxon]
  end

  def set_taxon_from_probable_taxon
    if identifications.size == 0 && taxon_id
      self.taxon = nil
      self.species_guess = nil
      return true
    end
    prob_taxon = probable_taxon( force: true )
    self.taxon_id = if ( !user.prefers_community_taxa? && prefers_community_taxon == nil ) || prefers_community_taxon == false
      # obs opted out or user opted out
      owners_identification.try(:taxon_id)
    elsif ( ct = community_taxon ) && prob_taxon && prob_taxon.rank_level.to_i < Taxon::SPECIES_LEVEL && prob_taxon.ancestor_ids.include?( ct.id )
      # prob_taxon was subspecific, using CID
      ct.id
    else
      # opted in
      prob_taxon.try(:id) || owners_identification.try(:taxon_id) || others_identifications.last.try(:taxon_id)
    end
    if taxon_id_changed? && (community_taxon_id_changed? || prefers_community_taxon_changed?)
      update_stats( skip_save: true )
      self.species_guess = if taxon
        taxon.common_name.try(:name) || taxon.name
      else
        nil
      end
    end
    true
  end

  def self.reassess_coordinates_for_observations_of( taxon, options = {} )
    batch_size = 500
    scope = Observation.with_identifications_of( taxon )
    scope.find_in_batches(batch_size: batch_size) do |batch|
      if options[:place]
        # using Elasticsearch for place filtering so we don't
        # get bogged down by huge geometries in Postgresql
        es_params = { id: batch, place_id: options[:place], per_page: batch_size }
        reassess_coordinates_of( Observation.page_of_results( es_params ) )
      else
        reassess_coordinates_of( batch )
      end
    end
  end

  def self.reassess_coordinates_of( observations )
    observations.each do |o|
      o.obscure_coordinates_for_threatened_taxa
      o.obscure_place_guess
      next unless o.coordinates_changed? || o.place_guess_changed?
      Observation.where( id: o.id ).update_all(
        latitude: o.latitude,
        longitude: o.longitude,
        private_latitude: o.private_latitude,
        private_longitude: o.private_longitude,
        geom: o.geom,
        private_geom: o.private_geom,
        place_guess: o.place_guess,
        private_place_guess: o.private_place_guess
      )
    end
    Observation.elastic_index!( ids: observations.map(&:id) )
  end

  def self.find_observations_of(taxon)
    Observation.joins(:taxon).
      where("observations.taxon_id = ? OR taxa.ancestry LIKE '#{taxon.ancestry}/#{taxon.id}%'", taxon).find_each do |o|
      yield(o)
    end
  end
  
  
  ##### Validations #########################################################
  #
  # Make sure the observation is not in the future.
  #
  def must_be_in_the_past
    return true if observed_on.blank?
    if observed_on > Time.now.in_time_zone(time_zone || user.time_zone).to_date
      errors.add(:observed_on, "can't be in the future")
    end
    true
  end
  
  #
  # Make sure the observation resolves to a single day.  Right now we don't
  # store ambiguity...
  #
  def must_not_be_a_range
    return if observed_on_string.blank?
    
    is_a_range = false
    begin  
      if tspan = Chronic.parse(observed_on_string, :context => :past, :guess => false)
        is_a_range = true if tspan.width.seconds > 1.day.seconds
      end
    rescue RuntimeError, ArgumentError
      # ignore parse errors, assume they're not spans
      return
    end
    
    # Special case: dates like '2004', which ordinarily resolve to today at 
    # 8:04pm
    observed_on_int = observed_on_string.gsub(/[^\d]/, '').to_i
    if observed_on_int > 1900 && observed_on_int <= Date.today.year
      is_a_range = true
    end
    
    if is_a_range
      errors.add(:observed_on, "must be a single day, not a range")
    end
  end
  
  def set_taxon_from_taxon_name
    return true if self.taxon_name.blank?
    return true if taxon_id
    self.taxon_id = single_taxon_id_for_name(self.taxon_name)
    true
  end
  
  def set_taxon_from_species_guess
    return true if species_guess =~ /\?$/
    return true unless species_guess_changed? && taxon_id.blank?
    return true if species_guess.blank?
    self.taxon_id = single_taxon_id_for_name(species_guess)
    true
  end
  
  def single_taxon_for_name(name)
    Taxon.single_taxon_for_name(name)
  end
  
  def single_taxon_id_for_name(name)
    Taxon.single_taxon_for_name(name).try(:id)
  end
  
  def set_latlon_from_place_guess
    return true unless latitude.blank? && longitude.blank?
    return true if place_guess.blank?
    return true if place_guess =~ /[a-cf-mo-rt-vx-z]/i # ignore anything with word chars other than NSEW
    return true unless place_guess.strip =~ /[.+,\s.+]/ # ignore anything without a legit separator
    matches = place_guess.strip.scan(COORDINATE_REGEX).flatten
    return true if matches.blank?
    case matches.size
    when 2 # decimal degrees
      self.latitude, self.longitude = matches
    when 4 # decimal minutes
      self.latitude = matches[0].to_i + matches[1].to_f/60.0
      self.longitude = matches[3].to_i + matches[4].to_f/60.0
    when 6 # degrees / minutes / seconds
      self.latitude = matches[0].to_i + matches[1].to_i/60.0 + matches[2].to_f/60/60
      self.longitude = matches[3].to_i + matches[4].to_i/60.0 + matches[5].to_f/60/60
    end
    self.latitude *= -1 if latitude.to_f > 0 && place_guess =~ /s/i
    self.longitude *= -1 if longitude.to_f > 0 && place_guess =~ /w/i
    true
  end
  
  def set_geom_from_latlon(options = {})
    if longitude.blank? || latitude.blank?
      self.geom = nil
    elsif options[:force] || longitude_changed? || latitude_changed?
      self.geom = "POINT(#{longitude} #{latitude})"
    end
    if private_latitude && private_longitude
      self.private_geom = "POINT(#{private_longitude} #{private_latitude})"
    elsif self.geom
      self.private_geom = self.geom
    else
      self.private_geom = nil
    end
    true
  end

  def self.place_guess_from_latlon( lat, lon, options = {} )
    sys_places = Observation.system_places_for_latlon( lat, lon, options )
    return if sys_places.blank?
    sys_places_codes = sys_places.map(&:code)
    user = options[:user]
    locale = options[:locale]
    locale ||= user.locale if user
    locale ||= I18n.locale
    first_name = if sys_places[0].admin_level == Place::COUNTY_LEVEL && sys_places_codes.include?( "US" )
      "#{sys_places[0].name} County"
    else
      I18n.t( sys_places[0].name, locale: locale, default: sys_places[0].name )
    end
    remaining_names = sys_places[1..-1].map do |p|
      if p.admin_level == Place::COUNTY_LEVEL && sys_places_codes.include?( "US" )
        "#{p.name} County"
      else
        translated_place = I18n.t(
          p.name,
          locale: locale,
          default: I18n.t(
            "places_name.#{p.name.underscore}",
            locale: locale,
            default: p.name
          )
        )
        p.code.blank? ? translated_place : p.code
      end
    end
    [first_name, remaining_names].flatten.join( ", " )
  end

  def set_place_guess_from_latlon
    return true unless place_guess.blank?
    return true if coordinates_private?
    if guess = Observation.place_guess_from_latlon( latitude, longitude, { acc: calculate_public_positional_accuracy, user: user } )
      self.place_guess = guess
    end
    true
  end
  
  def set_license
    return true if license_changed? && license.blank?
    self.license ||= user.preferred_observation_license
    self.license = nil unless LICENSE_CODES.include?(license)
    true
  end

  def trim_user_agent
    return true if user_agent.blank?
    self.user_agent = user_agent[0..254]
    true
  end
  
  def update_out_of_range_later
    if taxon_id_changed? && taxon.blank?
      update_out_of_range
    elsif latitude_changed? || private_latitude_changed? || taxon_id_changed?
      delay(:priority => USER_INTEGRITY_PRIORITY).update_out_of_range
    end
    true
  end
  
  def update_out_of_range
    set_out_of_range
    Observation.where(id: id).update_all(out_of_range: out_of_range)
  end
  
  def set_out_of_range
    if taxon_id.blank? || !georeferenced? || !TaxonRange.exists?(["taxon_id = ?", taxon_id])
      self.out_of_range = nil
      return
    end
    
    # buffer the point to accomodate simplified or slightly inaccurate ranges
    buffer_degrees = OUT_OF_RANGE_BUFFER / (2*Math::PI*Observation::PLANETARY_RADIUS) * 360.0
    
    self.out_of_range = if coordinates_obscured?
      TaxonRange.where(
        "taxon_ranges.taxon_id = ? AND ST_Distance(taxon_ranges.geom, ST_Point(?,?)) > ?",
        taxon_id, private_longitude, private_latitude, buffer_degrees
      ).exists?
    else
      TaxonRange.
        from("taxon_ranges, observations").
        where(
          "taxon_ranges.taxon_id = ? AND observations.id = ? AND ST_Distance(taxon_ranges.geom, observations.geom) > ?",
          taxon_id, id, buffer_degrees
        ).count > 0
    end
  end

  def set_uri
    if uri.blank?
      Observation.where(id: id).update_all(uri: FakeView.observation_url(id))
    end
    true
  end
  
  def update_default_license
    return true unless make_license_default.yesish?
    user.update_attribute(:preferred_observation_license, license)
    true
  end
  
  def update_all_licenses
    return true unless make_licenses_same.yesish?
    Observation.where(user_id: user_id).update_all(license: license)
    user.index_observations_later
    true
  end

  def update_taxon_counter_caches
    return true unless destroyed? || taxon_id_changed?
    taxon_ids = [taxon_id_was, taxon_id].compact.uniq
    unless taxon_ids.blank?
      Taxon.delay(:priority => INTEGRITY_PRIORITY).update_observation_counts(:taxon_ids => taxon_ids)
    end
    true
  end

  def update_user_counter_caches_after_create
    # For immediate gratification
    User.where( id: user_id ).update_all( observations_count: [user.observations_count.to_i + 1, 0].max )
    user.reload
    user.elastic_index!
    # For accuracy
    update_user_counter_caches
    true
  end

  def update_user_counter_caches_after_destroy
    return if bulk_delete
    User.where( id: user_id ).update_all( observations_count: [user.observations_count.to_i - 1, 0].max )
    user.reload
    user.elastic_index!
    update_user_counter_caches
    true
  end

  def update_user_counter_caches
    return if bulk_delete
    User.delay(
      unique_hash: { "User::update_observations_counter_cache": user_id },
      run_at: 1.minute.from_now
    ).update_observations_counter_cache( user_id )
    true
  end

  def delete_observations_places
    ObservationsPlace.where(observation_id: self.id).delete_all
  end

  def update_quality_metrics
    return true if skip_quality_metrics
    if captive_flag.yesish?
      QualityMetric.vote( user, self, QualityMetric::WILD, false )
    elsif captive_flag.noish? && force_quality_metrics
      QualityMetric.vote( user, self, QualityMetric::WILD, true )
    elsif captive_flag.noish? && ( qm = quality_metrics.detect{|m| m.user_id == user_id && m.metric == QualityMetric::WILD} )
      qm.update_attributes( agree: true)
    elsif force_quality_metrics && ( qm = quality_metrics.detect{|m| m.user_id == user_id && m.metric == QualityMetric::WILD} )
      qm.destroy
    end
    system_captive_vote = quality_metrics.detect{ |m| m.user_id.blank? && m.metric == QualityMetric::WILD }
    if probably_captive?
      QualityMetric.vote( nil, self, QualityMetric::WILD, false ) unless system_captive_vote
    elsif system_captive_vote
      system_captive_vote.destroy
    end
    true
  end
  
  def update_attributes(attributes)
    # hack around a weird android bug
    attributes.delete(:iconic_taxon_name)
    
    # MASS_ASSIGNABLE_ATTRIBUTES.each do |a|
    #   self.send("#{a}=", attributes.delete(a.to_s)) if attributes.has_key?(a.to_s)
    #   self.send("#{a}=", attributes.delete(a)) if attributes.has_key?(a)
    # end
    super(attributes)
  end
  
  def license_name
    return nil if license.blank?
    s = "Creative Commons "
    s += LICENSES.detect{|row| row.first == license}.try(:[], 1).to_s
    s
  end
  
  # I'm not psyched about having this stuff here, but it makes generating 
  # more compact JSON a lot easier.
  include ObservationsHelper
  include ActionView::Helpers::SanitizeHelper
  include ActionView::Helpers::TextHelper
  # include ActionController::UrlWriter
  include Rails.application.routes.url_helpers
  
  def image_url(options = {})
    url = observation_image_url(self, options.merge(size: "medium"))
    url =~ /^http/ ? url : nil
  end
  
  def obs_image_url
    image_url
  end

  def sound_url
    if s = sounds.detect{|s| s.is_a?( LocalSound ) }
      return s.file.url
    end
  end
  
  def short_description
    short_observation_description(self)
  end
  
  def scientific_name
    taxon.scientific_name.name if taxon && taxon.scientific_name
  end
  
  def common_name(options = {})
    options[:locale] ||= localize_locale
    options[:place] ||= localize_place
    taxon.common_name(options).name if taxon && taxon.common_name(options)
  end
  
  def url
    uri
  end
  
  def user_login
    user.login
  end
  
  def update_stats(options = {})
    idents = [self.identifications.to_a, options[:include]].flatten.compact.uniq
    current_idents = idents.select(&:current?)
    if taxon_id.blank?
      num_agreements    = 0
      num_disagreements = 0
    else
      nodes = community_taxon_nodes
      if node = nodes.detect{|n| n[:taxon].try(:id) == taxon_id}
        num_agreements = node[:cumulative_count]
        num_disagreements = node[:disagreement_count] + node[:conservative_disagreement_count]
        num_agreements -= 1 if current_idents.detect{|i| i.taxon_id == taxon_id && i.user_id == user_id}
        num_agreements = 0 if current_idents.count <= 1
        num_disagreements = 0 if current_idents.count <= 1
      else
        num_agreements    = current_idents.select{|ident| ident.is_agreement?(:observation => self)}.size
        num_disagreements = current_idents.select{|ident| ident.is_disagreement?(:observation => self)}.size
      end
    end
    
    # Kinda lame, but Observation#get_quality_grade relies on these numbers
    self.num_identification_agreements = num_agreements
    self.num_identification_disagreements = num_disagreements
    self.identifications_count = idents.size
    new_quality_grade = get_quality_grade
    self.quality_grade = new_quality_grade
    
    if !options[:skip_save] && (
        num_identification_agreements_changed? ||
        num_identification_disagreements_changed? ||
        quality_grade_changed? ||
        identifications_count_changed?)
      Observation.where(id: id).update_all(
        num_identification_agreements: num_agreements,
        num_identification_disagreements: num_disagreements,
        quality_grade: new_quality_grade,
        identifications_count: identifications_count)
      refresh_check_lists
      refresh_lists
    end
  end
  
  def self.update_stats_for_observations_of( taxon )
    taxon = Taxon.find_by_id(taxon) unless taxon.is_a?(Taxon)
    return unless taxon
    conditions = ["taxon_ancestors.ancestor_taxon_id = ?", taxon.id]
    obs_exist = Observation.
      joins( "INNER JOIN taxon_ancestors ON taxon_ancestors.taxon_id = observations.taxon_id" ).
      where( "observations.created_at > ?", taxon.created_at ).
      where( conditions ).exists?
    idents_exist = Identification.
      joins( "INNER JOIN taxon_ancestors ON taxon_ancestors.taxon_id = identifications.taxon_id" ).
      where( "identifications.created_at > ?", taxon.created_at ).
      where( conditions ).exists?
    return unless obs_exist || idents_exist
    result = Identification.elastic_search(
      filters: [ { bool: { should: [
        { term: { "taxon.ancestor_ids": taxon.id } },
        { term: { "observation.taxon.ancestor_ids": taxon.id } },
      ]}}],
      size: 0,
      aggregate: {
        obs: {
          terms: { field: "observation.id", size: 3000000 }
        }
      }
    )
    obs_ids = result.response.aggregations.obs.buckets.map{ |b| b[:key] }
    obs_ids.in_groups_of(1000) do |batch_ids|
      Observation.includes(:taxon, { identifications: :taxon }, :flags,
        { photos: :flags }, :quality_metrics, :sounds, :votes_for).where(id: batch_ids).find_each do |o|
        o.set_community_taxon
        o.update_stats(skip_save: true)
        if o.changed?
          o.skip_indexing = true
          o.save
          Identification.update_categories_for_observation( o )
        end
      end
      Observation.elastic_index!(ids: batch_ids)
    end
    Rails.logger.info "[INFO #{Time.now}] Finished Observation.update_stats_for_observations_of(#{taxon})"
  end
  
  def self.random_neighbor_lat_lon(lat, lon)
    precision = 10**5.0
    range = ((-1 * precision)..precision)
    half_cell = COORDINATE_UNCERTAINTY_CELL_SIZE / 2
    center_lat, center_lon = uncertainty_cell_center_latlon( lat, lon )
    [ center_lat + ((rand(range) / precision) * half_cell),
      center_lon + ((rand(range) / precision) * half_cell)]
  end

  # 
  # Coordinates of the southwest corner of the uncertainty cell for any given coordinates
  # 
  def self.uncertainty_cell_center_latlon( lat, lon )
    half_cell = COORDINATE_UNCERTAINTY_CELL_SIZE / 2
    # how many significant digits in the obscured coordinates (e.g. 5)
    # doing a floor with intervals of 0.2, then adding 0.1
    # so our origin is the center of a 0.2 square
    center_lat = lat - (lat % COORDINATE_UNCERTAINTY_CELL_SIZE) + half_cell
    center_lon = lon - (lon % COORDINATE_UNCERTAINTY_CELL_SIZE) + half_cell
    [center_lat, center_lon]
  end

  #
  # Distance of a diagonal from corner to corner across the uncertainty cell
  # for the given coordinates.
  #
  def self.uncertainty_cell_diagonal_meters( lat, lon )
    half_cell = COORDINATE_UNCERTAINTY_CELL_SIZE / 2
    center_lat, center_lon = uncertainty_cell_center_latlon( lat, lon )
    lat_lon_distance_in_meters( 
      center_lat - half_cell, 
      center_lon - half_cell, 
      center_lat + half_cell,
      center_lon + half_cell
    ).ceil
  end

  def private_sw_latlon
    return nil unless georeferenced?
    lat = private_latitude.blank? ? latitude : private_latitude
    lon = private_longitude.blank? ? longitude : private_longitude
    return [lat, lon] if positional_accuracy.blank?
    positional_accuracy_degrees = positional_accuracy / (2*Math::PI*PLANETARY_RADIUS) * 360.0
    [
      lat - positional_accuracy_degrees,
      lon - positional_accuracy_degrees,
    ]
  end

  def sw_latlon
    return nil unless georeferenced?
    return nil unless latitude
    if coordinates_obscured?
      half_cell = COORDINATE_UNCERTAINTY_CELL_SIZE / 2
      positional_accuracy_degrees = positional_accuracy.to_i / (2*Math::PI*PLANETARY_RADIUS) * 360.0
      max_half_cell = [half_cell, positional_accuracy_degrees].max
      return [
        private_latitude - max_half_cell,
        private_longitude - max_half_cell
      ]
    end
    private_sw_latlon
  end

  def private_ne_latlon
    return nil unless georeferenced?
    lat = private_latitude.blank? ? latitude : private_latitude
    lon = private_longitude.blank? ? longitude : private_longitude
    return [lat, lon] if positional_accuracy.blank?
    positional_accuracy_degrees = positional_accuracy / (2*Math::PI*PLANETARY_RADIUS) * 360.0
    [
      lat + positional_accuracy_degrees,
      lon + positional_accuracy_degrees,
    ]
  end

  def ne_latlon
    return nil unless georeferenced?
    return nil unless latitude
    if coordinates_obscured?
      half_cell = COORDINATE_UNCERTAINTY_CELL_SIZE / 2
      positional_accuracy_degrees = positional_accuracy.to_i / (2*Math::PI*PLANETARY_RADIUS) * 360.0
      max_half_cell = [half_cell, positional_accuracy_degrees].max
      return [
        private_latitude + max_half_cell,
        private_longitude + max_half_cell
      ]
    end
    private_ne_latlon
  end

  #
  # Distance of a diagonal from corner to corner across the uncertainty cell
  # for this observation's coordinates.
  # 
  def uncertainty_cell_diagonal_meters
    return nil unless georeferenced?
    lat = private_latitude || latitude
    lon = private_longitude || longitude
    Observation.uncertainty_cell_diagonal_meters( lat, lon )
  end

  def self.places_for_latlon( lat, lon, acc, options = {} )
    candidates = options[:candidates] || Place.containing_lat_lng( lat, lon )
    candidates = candidates.sort_by{|p| p.bbox_area || 0}

    # At present we use PostGIS GEOMETRY types, which are a bit stupid about
    # things crossing the dateline, so we need to do an app-layer check.
    # Converting to the GEOGRAPHY type would solve this, in theory.
    # Unfortunately this does NOT solve the problem of failing to select 
    # legit geoms that cross the dateline. GEOGRAPHY would solve that too.
    candidates.select do |p| 
      # HACK: bbox_contains_lat_lng_acc uses rgeo, which despite having a
      # spherical geometry factory, doesn't seem to allow spherical polygons
      # to use a contains? method, which means it doesn't really work for
      # polygons that cross the dateline, so... skip it until we switch to
      # geography, I guess.
      if p.straddles_date_line?
        true
      else
        p.bbox_contains_lat_lng_acc?(lat, lon, acc)
      end
    end
  end
  
  CNC_2018_PLACE_IDS = [
    124319, # City Nature Challenge 2018 Ahmedabad, India
    121393, # City Nature Challenge 2018: Amarillo
    60211,  # City Nature Challenge 2018: Austin
    122861, # City Nature Challenge 2018: Baltimore
    124697, # City Nature Challenge Maine 2018
    28784,  # Reto Naturalista Urbano 2018: Bogotá, D.C.
    118678, # City Nature Challenge 2018: Boston Area
    1733,   # City Nature Challenge 2018: Boulder
    123650, # City Nature Challenge 2018: Bristol & Bath
    124987, # City Nature Challenge 2018: Buenos Aires y alrededores
    2178,   # City Nature Challenge 2018: Cabarrus County, NC
    21588,  # City Nature Challenge 2018: Campo Grande
    124476, # City Nature Challenge 2018: Charlottesville
    57482,  # City Nature Challenge 2018: Chicago Wilderness Region
    122697, # City Nature Challenge 2018: Vancouver, British Columbia
    122777, # City Nature Challenge 2018: Cleveland
    125697, # City Nature Challenge 2018: Curitiba
    57484,  # City Nature Challenge 2018: Dallas/Fort Worth
    122714, # City Nature Challenge 2018: Denver Metro Area
    124794, # City Nature Challenge 2018: Twin Ports
    982,    # City Nature Challenge 2018: El Paso
    24546,  # City Nature Challenge 2018: Florianópolis
    125290, # City Nature Challenge 2018: Guimarães
    37720,  # City Nature Challenge 2018: Hermosillo
    7613,   # City Nature Challenge 2018: Hong Kong
    110679, # City Nature Challenge 2018: Houston
    123855, # City Nature Challenge 2018 Indianapolis
    124354, # Klang Valley City Nature Challenge 2018
    124339, # City Nature Challenge 2018: La Plata
    117586, # City Nature Challenge 2018: Southwest Louisiana
    66357,  # City Nature Challenge 2018: London
    962,    # City Nature Challenge 2018: Los Angeles
    94019,  # City Nature Challenge 2018: Lower Rio Grande Valley
    125291, # City Nature Challenge 2018: Manaus
    51507,  # City Nature Challenge 2018: Maui
    2345,   # City Nature Challenge 2018: Miami
    119106, # City Nature Challenge 2018: Minneapolis/St. Paul
    113429, # City Nature Challenge 2018: Monterrey Zona Metropolitana
    125114, # City Nature Challenge 2018: Mumbai
    121396, # City Nature Challenge 2018: Nashville
    674,    # City Nature Challenge 2018: New York City
    123395, # City Nature Challenge 2018: Omaha Metro
    124156, # City Nature Challenge 2018: Padova
    124663, # City Nature Challenge 2018: Palmer Station, Antarctica
    125789, # City Nature Challenge 2018: Pittsburgh
    124440, # City Nature Challenge 2018: Plymouth (UK)
    123944, # City Nature Challenge 2018: Prague
    118770, # City Nature Challenge 2018: Triangle Area
    124396, # City Nature Challenge 2018: Richmond
    23734,  # City Nature Challenge 2018: Rio de Janeiro
    124146, # City Nature Challenge 2018: Roma
    20640,  # City Nature Challenge 2018: Salvador
    121345, # City Nature Challenge 2018: San Antonio
    829,    # City Nature Challenge 2018: San Diego County
    54321,  # City Nature Challenge 2018: San Francisco Bay Area
    25311,  # City Nature Challenge 2018: São Paulo
    122789, # City Nature Challenge 2018: Seattle Metropolitan Area
    124153, # City Nature Challenge 2018: Southern Oregon
    124535, # City Nature Challenge 2018: St. Louis, MO
    2739,   # City Nature Challenge 2018: The Wasatch
    124352, # City Nature Challenge 2018: Tokyo
    123333, # City Nature Challenge 2018: Tulsa
    118683, # City Nature Challenge 2018: Washington, DC metro area
    27609   # City Nature Challenge 2018: Waterloo Region
  ]
  
  def places
    return [] unless georeferenced?
    candidates = observations_places.map(&:place).compact
    candidates.select do |p|
      p.bbox_privately_contains_observation?( self ) ||
      [Place::COUNTRY_LEVEL, Place::STATE_LEVEL, Place::COUNTY_LEVEL].include?( p.admin_level ) ||
      CNC_2018_PLACE_IDS.include?( p.id )
    end
  end
  
  def public_places
    return [] unless georeferenced?
    return [] if latitude.blank?
    candidates = observations_places.map(&:place).compact
    candidates.select do |p|
      p.bbox_publicly_contains_observation?( self ) ||
      [Place::COUNTRY_LEVEL, Place::STATE_LEVEL, Place::COUNTY_LEVEL].include?( p.admin_level ) ||
      CNC_2018_PLACE_IDS.include?( p.id )
    end
  end

  def self.system_places_for_latlon( lat, lon, options = {} )
    all_places = options[:places] || places_for_latlon( lat, lon, options[:acc] )
    all_places.select do |p|
      p.user_id.blank? && (
        [Place::COUNTRY_LEVEL, Place::STATE_LEVEL, Place::COUNTY_LEVEL].include?(p.admin_level) || 
        p.place_type == Place::PLACE_TYPE_CODES['Open Space']
      )
    end
  end

  # The places that are theoretically controlled by site admins
  def system_places(options = {})
    Observation.system_places_for_latlon( latitude, longitude, options.merge( acc: positional_accuracy ) )
  end

  def public_system_places( options = {} )
    Observation.system_places_for_latlon( latitude, longitude, options.merge( acc: positional_accuracy ) )
    public_places.select{|p| !p.admin_level.blank? }
  end

  def intersecting_places
    return [] unless georeferenced?
    lat = private_latitude || latitude
    lon = private_longitude || longitude
    @intersecting_places ||= Place.containing_lat_lng(lat, lon).sort_by{|p| p.bbox_area || 0}
  end

  {
    0     => "Undefined", 
    2     => "Street Segment", 
    4     => "Street", 
    5     => "Intersection", 
    6     => "Street", 
    7     => "Town", 
    8     => "State", 
    9     => "County",
    10    => "Local Administrative Area",
    12    => "Country",
    13    => "Island",
    14    => "Airport",
    15    => "Drainage",
    16    => "Land Feature",
    17    => "Miscellaneous",
    18    => "Nationality",
    19    => "Supername",
    20    => "Point of Interest",
    21    => "Region",
    24    => "Colloquial",
    25    => "Zone",
    26    => "Historical State",
    27    => "Historical County",
    29    => "Continent",
    33    => "Estate",
    35    => "Historical Town",
    36    => "Aggregate",
    100   => "Open Space",
    101   => "Territory"
  }.each do |code, type|
    define_method "place_#{type.underscore}" do
      public_places.detect{|p| p.place_type == code}
    end
    define_method "place_#{type.underscore}_name" do
      send("place_#{type.underscore}").try(:name)
    end
  end

  # Actually referring to Place::STATE_LEVEL seems to cause trouble here
  [1, 2].each do |admin_level|
    define_method "place_admin#{admin_level}" do
      public_places.detect{|p| p.admin_level == admin_level}
    end
    define_method "place_admin#{admin_level}_name" do
      send( "place_admin#{admin_level}" ).try(:name)
    end
  end

  def taxon_and_ancestors
    taxon ? taxon.self_and_ancestors.to_a : []
  end
  
  def mobile?
    return false unless user_agent
    MOBILE_APP_USER_AGENT_PATTERNS.each do |pattern|
      return true if user_agent =~ pattern
    end
    false
  end
  
  def device_name
    return "unknown" unless user_agent
    if user_agent =~ ANDROID_APP_USER_AGENT_PATTERN
      "iNaturalist Android App"
    elsif user_agent =~ FISHTAGGER_APP_USER_AGENT_PATTERN
      "Fishtagger iPhone App"
    elsif user_agent =~ IPHONE_APP_USER_AGENT_PATTERN
      "iNaturalist iPhone App"
    else
      "web browser"
    end
  end
  
  def device_url
    return unless user_agent
    if user_agent =~ FISHTAGGER_APP_USER_AGENT_PATTERN
      "http://itunes.apple.com/us/app/fishtagger/id582724178?mt=8"
    elsif user_agent =~ IPHONE_APP_USER_AGENT_PATTERN
      "http://itunes.apple.com/us/app/inaturalist/id421397028?mt=8"
    elsif user_agent =~ ANDROID_APP_USER_AGENT_PATTERN
      "https://market.android.com/details?id=org.inaturalist.android"
    end
  end
  
  def owners_identification
    if identifications.loaded?
      # if idents are loaded, the most recent current identification might be a new record
      identifications.sort_by{|i| i.created_at || 1.minute.from_now}.select {|ident| 
        ident.user_id == user_id && ident.current?
      }.last
    else
      identifications.current.by(user_id).last
    end
  end

  def others_identifications
    if identifications.loaded?
      identifications.select do |i|
        i.current? && i.user_id != user_id
      end
    else
      identifications.current.not_by(user_id)
    end
  end

  def method_missing(method, *args, &block)
    return super unless method.to_s =~ /^field:/ || method.to_s =~ /^taxon_[^=]+/ || method.to_s =~ /^ident_by_/
    if method.to_s =~ /^field:/
      of_name = ObservationField.normalize_name( method.to_s[/^field\:(.+)/, 1] )
      ofv = observation_field_values.detect{|ofv| ofv.observation_field.normalized_name == of_name}
      if ofv
        return ofv.taxon ? ofv.taxon.name : ofv.value
      end
    elsif method.to_s =~ /^taxon_/ && !self.class.instance_methods.include?(method) && taxon
      return taxon.send(method.to_s.gsub(/^taxon_/, ''))
    elsif method.to_s =~ /^ident_by_/ && !self.class.instance_methods.include?( method )
      user_id = method.to_s[/ident_by_([^\:]+)/, 1]
      return unless user_id
      ident = if user_id.to_i > 0
        identifications.detect{|i| i.current && i.user_id == user_id.to_i }
      else
        identifications.detect{|i| i.current && i.user.login == user_id }
      end
      return unless ident
      ident_method = method.to_s[/ident_by_([^\:]+)\:(.+)/, 2]
      return unless ident_method
      return ident.send( ident_method )
    end
    super
  end

  def respond_to?(method, include_private = false)
    @@class_methods_hash ||= Hash[ self.class.instance_methods.map{ |h| [ h.to_sym, true ] } ]
    @@class_columns_hash ||= Hash[ self.class.column_names.map{ |h| [ h.to_sym, true ] } ]
    if @@class_methods_hash[method.to_sym] || @@class_columns_hash[method.to_sym]
      return super
    end
    return super unless method.to_s =~ /^field:/ || method.to_s =~ /^taxon_[^=]+/
    if method.to_s =~ /^field:/
      of_name = method.to_s.split(':').last
      ofv = observation_field_values.detect{|ofv| ofv.observation_field.normalized_name == of_name}
      return !ofv.blank?
    elsif method.to_s =~ /^taxon_/ && taxon
      return taxon.respond_to?(method.to_s.gsub(/^taxon_/, ''), include_private)
    end
    super
  end

  def merge(reject, options = {})
    mutable_columns = self.class.column_names - %w(id created_at updated_at uuid)
    mutable_columns.each do |column|
      self.send("#{column}=", reject.send(column)) if send(column).blank?
    end
    if options[:skip_identifications]
      reject.identifications.delete_all
    else
      reject.identifications.update_all("current = false")
    end
    merge_has_many_associations(reject)
    reject.destroy
    unless options[:skip_identifications]
      identifications.group_by{|ident| [ident.user_id, ident.taxon_id]}.each do |pair, idents|
        c = idents.sort_by(&:id).last
        c.update_attributes(:current => true)
      end
    end
    save!
  end

  def create_observation_review
    return true unless taxon
    return true unless taxon_id_was.blank?
    return true unless editing_user_id && editing_user_id == user_id
    ObservationReview.where( observation_id: id, user_id: user_id ).first_or_create.touch
    true
  end

  def reassess_annotations
    return true unless taxon_id_changed?
    annotations.each do |a|
      a.destroy unless a.valid?
    end
    true
  end

  def create_deleted_observation
    DeletedObservation.create(
      :observation_id => id,
      :user_id => user_id
    )
    true
  end

  def build_observation_fields_from_tags(tags)
    tags.each do |tag|
      np, value = tag.split('=')
      next unless np && value
      namespace, predicate = np.split(':')
      predicate = namespace if predicate.blank?
      next if predicate.blank?
      of = ObservationField.where("lower(name) = ?", predicate.downcase).first
      next unless of
      next if self.observation_field_values.detect{|ofv| ofv.observation_field_id == of.id}
      if of.datatype == ObservationField::TAXON
        t = Taxon.single_taxon_for_name(value)
        next unless t
        value = t.id
      end
      ofv = ObservationFieldValue.new(observation: self, observation_field: of, value: value)
      self.observation_field_values.build(ofv.attributes) if ofv.valid?
    end
  end

  def fields_addable_by?(u)
    return false unless u.is_a?(User) 
    return true if user.preferred_observation_fields_by == User::PREFERRED_OBSERVATION_FIELDS_BY_ANYONE
    return true if user.preferred_observation_fields_by == User::PREFERRED_OBSERVATION_FIELDS_BY_CURATORS && u.is_curator?
    u.id == user_id
  end

  def set_coordinates
    if self.geo_x.present? && self.geo_y.present? && self.coordinate_system.present?
      # Perform the transformation
      # transfrom from `self.coordinate_system`
      from = RGeo::CoordSys::Proj4.new(self.coordinate_system)

      # ... to WGS84
      to = RGeo::CoordSys::Proj4.new(WGS84_PROJ4)

      # Returns an array of lat, lon
      transform = RGeo::CoordSys::Proj4.transform_coords(from, to, self.geo_x.to_d, self.geo_y.to_d)

      # Set the transfor
      self.longitude, self.latitude = transform
    end
    true
  end

  # Required for use of the sanitize method in
  # ObservationsHelper#short_observation_description
  def self.white_list_sanitizer
    @white_list_sanitizer ||= HTML::WhiteListSanitizer.new
  end
  
  def self.update_for_taxon_change(taxon_change, options = {}, &block)
    input_taxon_ids = taxon_change.input_taxa.map(&:id)
    scope = Observation.where("observations.taxon_id IN (?)", input_taxon_ids)
    scope = scope.by(options[:user]) if options[:user]
    unless options[:records].blank?
      record_ids = options[:records].to_a.map{|r| r.is_a?( Observation ) ? r.id : r.to_i }.compact.uniq
      scope = scope.where( "observations.id IN (?)", record_ids )
    end
    scope = scope.includes( :user, :identifications, :observations_places )
    scope.find_each do |observation|
      if observation.owners_identification && input_taxon_ids.include?( observation.owners_identification.taxon_id )
        if output_taxon = taxon_change.output_taxon_for_record( observation )
          Identification.create(
            user: observation.user,
            observation: observation,
            taxon: output_taxon,
            taxon_change: taxon_change
          )
        end
      end
      yield(observation) if block_given?
    end
  end

  # 2014-01 I tried improving performance by loading ancestor taxa for each
  # batch, but it didn't really speed things up much
  def self.generate_csv(scope, options = {})
    fname = options[:fname] || "observations.csv"
    fpath = options[:path] || File.join(options[:dir] || Dir::tmpdir, fname)
    FileUtils.mkdir_p File.dirname(fpath), :mode => 0755
    columns = options[:columns] || CSV_COLUMNS
    CSV.open(fpath, 'w') do |csv|
      csv << columns
      scope.find_each(batch_size: 500) do |observation|
        csv << columns.map do |c|
          c = "cached_tag_list" if c == "tag_list"
          observation.send(c) rescue nil
        end
      end
    end
    fpath
  end

  def self.generate_csv_for(record, options = {})
    fname = options[:fname] || "#{record.to_param}-observations.csv"
    fpath = options[:path] || File.join(options[:dir] || Dir::tmpdir, fname)
    tmp_path = File.join(Dir::tmpdir, fname)
    FileUtils.mkdir_p File.dirname(tmp_path), :mode => 0755
    columns = CSV_COLUMNS

    # ensure private coordinates are hidden unless they shouldn't be
    viewer_curates_project = record.is_a?(Project) && record.curated_by?(options[:user])
    viewer_is_owner = record.is_a?(User) && record == options[:user]
    unless viewer_curates_project || viewer_is_owner
      columns = columns.select{|c| c !~ /^private_/}
    end

    # generate the csv
    if record.respond_to?(:generate_csv)
      record.generate_csv(tmp_path, columns, viewer: options[:user])
    else
      scope = record.observations.
        includes(:taxon).
        includes(observation_field_values: :observation_field)
      unless record.is_a?(User) && options[:user] === record
        scope = scope.includes(project_observations: :stored_preferences).
          includes(user: {project_users: :stored_preferences})
      end
      generate_csv(scope, :path => tmp_path, :fname => fname, :columns => columns, :viewer => options[:user])
    end

    FileUtils.mkdir_p File.dirname(fpath), :mode => 0755
    if tmp_path != fpath
      FileUtils.mv tmp_path, fpath
    end
    fpath
  end

  def self.generate_csv_for_cache_key(record, options = {})
    "#{record.class.name.underscore}_#{record.id}"
  end

  def public_positional_accuracy
    if coordinates_obscured? && !read_attribute(:public_positional_accuracy)
      update_public_positional_accuracy
    end
    read_attribute(:public_positional_accuracy)
  end

  def update_public_positional_accuracy
    update_column(:public_positional_accuracy, calculate_public_positional_accuracy)
  end

  def calculate_public_positional_accuracy
    if coordinates_obscured?
      [ positional_accuracy.to_i, uncertainty_cell_diagonal_meters, 0 ].max
    elsif !positional_accuracy.blank?
      positional_accuracy
    end
  end

  def inaccurate_location?
    if metric = quality_metric_score(QualityMetric::LOCATION)
      return metric <= 0.5
    end
    false
  end

  def update_mappable
    update_column(:mappable, calculate_mappable)
  end

  def calculate_mappable
    return false if latitude.blank? && longitude.blank?
    return false if public_positional_accuracy && public_positional_accuracy > uncertainty_cell_diagonal_meters
    return false if inaccurate_location?
    return false unless passes_quality_metric?( QualityMetric::EVIDENCE )
    return false unless appropriate?
    if community_taxon && taxon &&
        !community_taxon.self_and_ancestor_ids.include?( taxon.id ) &&
        !taxon.self_and_ancestor_ids.include?( community_taxon.id )
      return false
    end
    true
  end

  def update_observations_places
    Observation.update_observations_places(ids: [ id ])
    # reload the association since we added the records using SQL
    observations_places(true)
  end

  def set_taxon_photo
    return true unless research_grade? && quality_grade_changed?
    if taxon && !taxon.photos.any?
      community_taxon.delay( priority: INTEGRITY_PRIORITY, run_at: 1.day.from_now ).set_photo_from_observations
    end
    true
  end

  def self.update_observations_places(options = { })
    filter_scope = options.delete(:scope)
    scope = (filter_scope && filter_scope.is_a?(ActiveRecord::Relation)) ?
      filter_scope : self.all
    if filter_ids = options.delete(:ids)
      if filter_ids.length > 1000
        # call again for each batch, then return
        filter_ids.each_slice(1000) do |slice|
          update_observations_places(options.merge(ids: slice))
        end
        return
      end
      scope = scope.where(id: filter_ids)
    end
    scope.select(:id).find_in_batches(options) do |batch|
      ids = batch.map(&:id)
      Observation.transaction do
        connection.execute("DELETE FROM observations_places
          WHERE observation_id IN (#{ ids.join(',') })")
        connection.execute("INSERT INTO observations_places (observation_id, place_id)
          SELECT DISTINCT o.id, pg.place_id FROM observations o
          JOIN place_geometries pg ON ST_Intersects(pg.geom, o.private_geom)
          WHERE o.id IN (#{ ids.join(',') })
          AND pg.place_id IS NOT NULL
          AND NOT EXISTS (
            SELECT observation_id FROM observations_places
            WHERE place_id = pg.place_id AND observation_id = o.id
          )")
      end
    end
  end

  def observation_photos_finished_processing
    observation_photos.select do |op|
      ! (op.photo.is_a?(LocalPhoto) && op.photo.processing?)
    end
  end

  def interpolate_coordinates
    return unless time_observed_at
    scope = user.observations.where("latitude IS NOT NULL or private_latitude IS NOT NULL")
    prev_obs = scope.where("time_observed_at < ?", time_observed_at).order("time_observed_at DESC").first
    next_obs = scope.where("time_observed_at > ?", time_observed_at).order("time_observed_at ASC").first
    return unless prev_obs && next_obs
    prev_lat = prev_obs.private_latitude || prev_obs.latitude
    prev_lon = prev_obs.private_longitude || prev_obs.longitude
    next_lat = next_obs.private_latitude || next_obs.latitude
    next_lon = next_obs.private_longitude || next_obs.longitude

    # time-weighted interpolation between prev and next observations
    weight = (next_obs.time_observed_at - time_observed_at) / (next_obs.time_observed_at-prev_obs.time_observed_at)
    new_lat = (1-weight)*next_lat + weight*prev_lat
    new_lon = (1-weight)*next_lon + weight*prev_lon
    self.latitude = new_lat
    self.longitude = new_lon

    # we can only set a new uncertainty if the uncertainty of the two points are known
    if prev_obs.positional_accuracy && next_obs.positional_accuracy
      f = RGeo::Geographic.simple_mercator_factory
      prev_point = f.point(prev_lon, prev_lat)
      next_point = f.point(next_lon, next_lat)
      interpolation_uncertainty = prev_point.distance(next_point)/2.0
      new_acc = Math.sqrt(interpolation_uncertainty**2 + prev_obs.positional_accuracy**2 + next_obs.positional_accuracy**2)
      self.positional_accuracy = new_acc
    end
  end

  def self.as_csv(scope, methods, options = {})
    CSV.generate do |csv|
      csv << methods
      scope.each do |item|
        # image_url gets options, which will include an SSL boolean
        csv << methods.map{ |m| m == :image_url ? item.send(m, options) : item.send(m) }
      end
    end
  end

  def community_taxon_at_species_or_lower?
    community_taxon && community_taxon.rank_level && community_taxon.rank_level <= Taxon::SPECIES_LEVEL
  end

  def community_taxon_at_family_or_lower?
    community_taxon && community_taxon.rank_level && community_taxon.rank_level <= Taxon::FAMILY_LEVEL
  end

  def community_taxon_below_family?
    community_taxon && community_taxon.rank_level && community_taxon.rank_level < Taxon::FAMILY_LEVEL
  end

  def needs_id_upvotes_count
    votes_for.loaded? ?
     votes_for.select{ |v| v.vote_flag? && v.vote_scope == "needs_id" }.size :
     get_upvotes(vote_scope: "needs_id").size
  end

  def needs_id_downvotes_count
    votes_for.loaded? ?
      votes_for.select{ |v| !v.vote_flag? && v.vote_scope == "needs_id" }.size :
      get_downvotes(vote_scope: "needs_id").size
  end

  def needs_id_vote_score
    uvotes = needs_id_upvotes_count
    dvotes = needs_id_downvotes_count
    if uvotes == 0 && dvotes == 0
      nil
    elsif uvotes == 0
      0
    elsif dvotes == 0
      1
    else
      uvotes.to_f / (uvotes + dvotes)
    end
  end

  def voted_out_of_needs_id?
    needs_id_downvotes_count > needs_id_upvotes_count
  end

  def voted_in_to_needs_id?
    needs_id_upvotes_count > needs_id_downvotes_count
  end

  def needs_id?
    quality_grade == NEEDS_ID
  end

  def casual?
    quality_grade == CASUAL
  end

  def flagged_with(flag, options)
    quality_grade_will_change!
    save
    evaluate_new_flag_for_spam(flag)
  end

  def mentioned_users
    return [ ] unless description
    description.mentioned_users
  end

  def previously_mentioned_users
    return [ ] if description_was.blank?
    description.mentioned_users & description_was.to_s.mentioned_users
  end

  # Show count of all faves on this observation. cached_votes_total stores the
  # count of all votes without a vote_scope, which for an Observation means
  # the faves, but since that might vary from model to model based on how we
  # use acts_as_votable, faves_count seems clearer.
  def faves_count
    cached_votes_total
  end

  def probably_captive?
    target_taxon = community_taxon || taxon
    return false unless target_taxon
    if target_taxon.rank_level.blank? || target_taxon.rank_level.to_i > Taxon::GENUS_LEVEL
      return false
    end
    place = system_places.detect do |p|
      [
        Place::COUNTRY_LEVEL, Place::STATE_LEVEL, Place::COUNTY_LEVEL
      ].include?( p.admin_level )
    end
    return false unless place
    buckets = Observation.elastic_search(
      filters: [
        { term: { "taxon.ancestor_ids": target_taxon.id } },
        { term: { place_ids: place.id } },
      ],
      # earliest_sort_field: "id",
      size: 0,
      aggregate: {
        captive: {
          terms: { field: "captive", size: 15 }
        }
      }
    ).results.response.response.aggregations.captive.buckets
    captive_stats = Hash[ buckets.map{ |b| [ b["key"], b["doc_count" ] ] } ]
    total = captive_stats.values.sum
    ratio = captive_stats[1].to_f / total
    # puts "total: #{total}, ratio: #{ratio}, place: #{place}"
    total > 10 && ratio >= 0.8
  end

  def application_id_to_index
    return oauth_application_id if oauth_application_id
    if user_agent =~ IPHONE_APP_USER_AGENT_PATTERN
      return OauthApplication.inaturalist_iphone_app.try(:id)
    end
    if user_agent =~ ANDROID_APP_USER_AGENT_PATTERN
      return OauthApplication.inaturalist_android_app.try(:id)
    end
  end

  def owners_identification_from_vision
    owners_identification.try(:vision)
  end

  def owners_identification_from_vision=( val )
    self.owners_identification_from_vision_requested = val
  end

  def reindex_identifications
    Identification.elastic_index!( ids: identification_ids )
  end

  # The intent here is to keep the observations_count in the Places index
  # *roughly* up-to-date. So these jobs probably won't be queued after
  # observation creation b/c the ObservationsPlace records won't have been made,
  # and no place should be re-indexed more than once a day.
  def reindex_places
    return true if skip_indexing
    places.each_with_index do |p,i|
      # Queue jobs with a little offset we don't end up running intense API
      # calls at the same time
      p.delay(
        run_at: ( 1.day + i.minutes ).from_now,
        priority: INTEGRITY_PRIORITY,
        queue: "slow",
        unique_hash: { "Place::elastic_index": p.id }
      ).elastic_index!
    end
    true
  end

  def reindex_projects
    return true if skip_indexing
    projects.each_with_index do |p,i|
      # Queue jobs with a little offset we don't end up running intense API
      # calls at the same time
      p.delay(
        run_at: ( 1.day + i.minutes ).from_now,
        priority: INTEGRITY_PRIORITY,
        queue: "slow",
        unique_hash: { "Project::elastic_index": p.id }
      ).elastic_index!
    end
    true
  end

  def user_viewed_updates(user_id)
    obs_updates = UpdateAction.where(resource: self)
    UpdateAction.user_viewed_updates(obs_updates, user_id)
  end

  def self.dedupe_for_user(user, options = {})
    unless user.is_a?(User)
      u = User.find_by_id(user) 
      u ||= User.find_by_login(user)
      user = u
    end
    return unless user
    sql = <<-SQL
      SELECT 
        array_agg(id) AS observation_ids
      FROM
        observations
      WHERE
        user_id = #{user.id}
        AND taxon_id IS NOT NULL
        AND observed_on_string IS NOT NULL AND observed_on_string != ''
        AND private_geom IS NOT NULL
      GROUP BY 
        user_id,
        taxon_id, 
        observed_on_string, 
        private_geom
      HAVING count(*) > 1;
    SQL
    deleted = 0
    start = Time.now
    Observation.connection.execute(sql).each do |row|
      ids = row['observation_ids'].gsub(/[\{\}]/, '').split(',').map(&:to_i).sort
      puts "Found duplicates: #{ids.join(',')}" if options[:debug]
      keeper_id = ids.shift
      puts "\tKeeping #{keeper_id}" if options[:debug]
      unless options[:test]
        Observation.find(ids).each do |o|
          puts "\tDeleting #{o.id}" if options[:debug]
          o.destroy
        end
      end
      deleted += ids.size
    end
    puts "Deleted #{deleted} observations in #{Time.now - start}s" if options[:debug]
  end

  def self.index_observations_for_user(user_id)
    Observation.elastic_index!( scope: Observation.by( user_id ) )
  end

  def self.refresh_es_index
    Observation.__elasticsearch__.refresh_index! unless Rails.env.test?
  end

end
