class ChallengeClaim < ActiveRecord::Base
  # We use "-1" to represent all the requested items matching 
  ALL = -1

  belongs_to :claiming_user, :class_name => "User", :inverse_of => :request_claims
  belongs_to :collection
  belongs_to :request_signup, :class_name => "ChallengeSignup"
  belongs_to :request_prompt, :class_name => "Prompt"
  belongs_to :creation, :polymorphic => true

  scope :for_request_signup, lambda {|signup|
    {:conditions => ['request_signup_id = ?', signup.id]}
  }

  scope :by_claiming_user, lambda {|user|
    {
      :select => "DISTINCT challenge_claims.*",
      :joins => "INNER JOIN users ON challenge_claims.claiming_user_id = users.id",
      :conditions => ['users.id = ?', user.id]
    }
  }

  scope :in_collection, lambda {|collection| {:conditions => ['challenge_claims.collection_id = ?', collection.id] }}
  
  scope :with_request, {:conditions => ["request_signup_id IS NOT NULL"]}
  scope :with_no_request, {:conditions => ["request_signup_id IS NULL"]}

  REQUESTING_PSEUD_JOIN = "INNER JOIN challenge_signups ON (challenge_claims.request_signup_id = challenge_signups.id)
                           INNER JOIN pseuds ON challenge_signups.pseud_id = pseuds.id"

  CLAIMING_PSEUD_JOIN = "INNER JOIN users ON challenge_claims.claiming_user_id = users.id"

  COLLECTION_ITEMS_JOIN = "INNER JOIN collection_items ON (collection_items.collection_id = challenge_claims.collection_id AND 
                                                           collection_items.item_id = challenge_claims.creation_id AND 
                                                           collection_items.item_type = challenge_claims.creation_type)"

  COLLECTION_ITEMS_LEFT_JOIN =  "LEFT JOIN collection_items ON (collection_items.collection_id = challenge_claims.collection_id AND 
                                                                collection_items.item_id = challenge_claims.creation_id AND 
                                                                collection_items.item_type = challenge_claims.creation_type)"

  
  scope :order_by_date, order("created_at ASC")

  def self.order_by_requesting_pseud(dir="ASC")
    joins(REQUESTING_PSEUD_JOIN).order("pseuds.name #{dir}")
  end
  
  def self.order_by_offering_pseud(dir="ASC")
    joins(CLAIMING_PSEUD_JOIN).order("pseuds.name #{dir}")
  end

  WORKS_JOIN = "INNER JOIN works ON works.id = challenge_claims.creation_id AND challenge_claims.creation_type = 'Work'"
  WORKS_LEFT_JOIN = "LEFT JOIN works ON works.id = challenge_claims.creation_id AND challenge_claims.creation_type = 'Work'"
  
  scope :fulfilled,
    joins(COLLECTION_ITEMS_JOIN).joins(WORKS_JOIN).
    where('challenge_claims.creation_id IS NOT NULL AND collection_items.user_approval_status = ? AND collection_items.collection_approval_status = ? AND works.posted = 1',
                    CollectionItem::APPROVED, CollectionItem::APPROVED)

  
  scope :posted, joins(WORKS_JOIN).where("challenge_claims.creation_id IS NOT NULL AND works.posted = 1")

  # should be faster than unfulfilled scope because no giant left joins
  def self.unfulfilled_in_collection(collection)
    fulfilled_ids = ChallengeClaim.in_collection(collection).fulfilled.value_of(:id)
    fulfilled_ids.empty? ? in_collection(collection) : in_collection(collection).where("challenge_claims.id NOT IN (?)", fulfilled_ids)
  end
  
  # faster than unposted scope because no left join!
  def self.unposted_in_collection(collection)
    posted_ids = ChallengeClaim.in_collection(collection).posted.value_of(:id)
    posted_ids.empty? ? in_collection(collection) : in_collection(collection).where("challenge_claims.creation_id IS NULL OR challenge_claims.id NOT IN (?)", posted_ids)
  end    
    
  # has to be a left join to get works that don't have a collection item
  scope :unfulfilled,
    joins(COLLECTION_ITEMS_LEFT_JOIN).joins(WORKS_LEFT_JOIN).
    where('challenge_claims.creation_id IS NULL OR collection_items.user_approval_status != ? OR collection_items.collection_approval_status != ? OR works.posted = 0', CollectionItem::APPROVED, CollectionItem::APPROVED)

  # ditto
  scope :unposted, joins(WORKS_LEFT_JOIN).where("challenge_claims.creation_id IS NULL OR works.posted = 0")

  scope :unstarted, where("challenge_claims.creation_id IS NULL")

  def self.unposted_for_user(user)
    all_claims = ChallengeClaim.by_claiming_user(user)
    posted_ids = all_claims.posted.value_of(:id)
    all_claims.where("challenge_claims.id NOT IN (?)", posted_ids)
  end

  
  def get_collection_item
    return nil unless self.creation
    CollectionItem.find(:first, :conditions => ["collection_id = ? AND item_id = ? AND item_type = ?", self.collection_id, self.creation_id, self.creation_type])
  end
  
  def fulfilled?
    self.creation && (item = get_collection_item) && item.approved?
  end

  include Comparable
  def <=>(other)
    return -1 if self.request_signup.nil? && other.request_signup
    return 1 if other.request_signup.nil? && self.request_signup
    return self.request_byline.downcase <=> other.request_byline.downcase
  end
  
  def title
    if self.request_prompt.anonymous?
      title = "#{self.collection.title} (Anonymous)"
    else
      title = "#{self.collection.title} (#{self.request_byline})"
    end
    title += " - " + self.request_prompt.tag_unlinked_list
    return title
  end
  
  def claiming_user
    User.find_by_id(claiming_user_id)
  end
  
  def claiming_pseud
    User.find_by_id(claiming_user_id).default_pseud
  end
  
  def requesting_pseud
    request_signup ? request_signup.pseud : nil
  end
  
  def claim_byline
    User.find_by_id(claiming_user_id).default_pseud.byline
  end
  
  def request_byline
    request_signup ? request_signup.pseud.byline : "- None -"
  end
  
  def user_allowed_to_destroy?(current_user)
    (self.claiming_user == current_user) || self.collection.user_is_maintainer?(current_user)
  end

end
