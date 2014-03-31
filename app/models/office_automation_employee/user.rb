require 'csv'

module OfficeAutomationEmployee
  class User 
    include Mongoid::Document
    include Mongoid::Search
    include Mongoid::Slug

    #Send mail when user updates following fields
    UPDATED_FIELDS = ['image', 'date_of_joining', 'designation']

    # Include default devise modules. Others available are:
    # :confirmable, :lockable, :timeoutable and :omniauthable
    devise :invitable, :database_authenticatable, :registerable,
      :recoverable, :rememberable, :trackable, :confirmable, :validatable, :async

    mount_uploader :image, FileUploader

    ## Database authenticatable
    field :email,              default: ""
    slug :username
    field :encrypted_password, default: ""

    ## Recoverable
    field :reset_password_token
    field :reset_password_sent_at

    ## Rememberable
    field :remember_created_at, type: Time

    ## Trackable
    field :sign_in_count,      type: Integer, default: 0
    field :current_sign_in_at, type: Time
    field :last_sign_in_at,    type: Time
    field :current_sign_in_ip
    field :last_sign_in_ip

    ## Confirmable
    field :confirmation_token
    field :confirmed_at,         type: Time
    field :confirmation_sent_at, type: Time
    field :unconfirmed_email # Only if using reconfirmable

    ## Invitable
    field :invitation_token
    field :invitation_created_at, type: Time
    field :invitation_sent_at, type: Time
    field :invitation_accepted_at, type: Time
    field :invitation_limit, type: Integer

    index( {invitation_token: 1}, { background: true } )
    index( {invitation_by_id: 1}, { background: true } )

    ## Lockable
    # field :failed_attempts, :type => Integer, :default => 0 # Only if lock strategy is :failed_attempts
    # field :unlock_token,    :type => String # Only if unlock strategy is :email or :both
    # field :locked_at,       :type => Time

    # user-fields
    field :status, default: 'Pending'
    field :roles, type: Array
    field :invalid_csv_data, type: Array
    field :csv_downloaded, type: Boolean, default: true
    field :image

    # validations
    validates :roles, presence: true


    # relationships
    embeds_one :profile, class_name: 'OfficeAutomationEmployee::Profile'
    embeds_one :personal_profile, class_name: 'OfficeAutomationEmployee::PersonalProfile'
    belongs_to :company, class_name: 'OfficeAutomationEmployee::Company'
    embeds_many :attachments, class_name: 'OfficeAutomationEmployee::Attachment', cascade_callbacks: true

    accepts_nested_attributes_for :profile
    accepts_nested_attributes_for :personal_profile
    accepts_nested_attributes_for :attachments

    search_in :email, profile: [:first_name, :last_name]
   
    after_update :send_mail

    def role?(role)
      roles.include? role.humanize
    end

    def username
      email.split('@')[0]
    end

    def fullname
      "#{profile.first_name} #{profile.middle_name} #{profile.last_name}" unless profile.nil?
    end

    def full_address address
      "#{address.address} \n #{address.city.humanize}, #{address.state.humanize} \n #{address.country}, #{address.pincode}"
    end

    def invite_by_fields(fields)
      invalid_email_count, total_email_fields = 0, 0
      fields.each_value do |invitee|
        if invitee[:_destroy] == 'false'
          user = company.users.create email: invitee[:email], roles: [company.roles.find(invitee[:roles]).name]
          user.errors.messages.keys.include?(:email) ? invalid_email_count += 1 : user.invite!(self)
          total_email_fields += 1
        end
      end
      [invalid_email_count, total_email_fields]
    end

    def invite_by_csv(file)
      update_attributes csv_downloaded: true, invalid_csv_data: Array.new
      CSV.foreach(file.path, headers: true) do |row|
        if row.headers != ["email", "roles"]
          push(invalid_csv_data: row.to_s.chomp) if row.present?
          next
        end
        user = company.users.create email: row["email"], roles: [row['roles'].try(:humanize)].compact

        invalid_user = user.errors.messages.keys.include?(:email) || user.errors.messages.keys.include?(:roles) || company.roles.where(name: row['roles'].try(:humanize)).none?
        invalid_user ? push(invalid_csv_data: row.to_s.chomp) : user.invite!(self)
      end
      update_attributes csv_downloaded: false if invalid_csv_data.present?
      $. - 1  # $. is last row number from csv file
    end

    def to_csv csv_data
      CSV.generate do |csv|
        csv << ["email", "roles"]
        csv_data.each do |row|
          csv << row.split(',')
        end
      end
    end

    def send_mail
      personal_profile_changes = self.personal_profile ? self.personal_profile.changes : {}
      profile_changes = self.profile ? self.profile.changes : {}
      @updated_attributes = self.changes.merge(personal_profile_changes).merge(profile_changes)
      @updated_attributes.reject!{|k,v| !UPDATED_FIELDS.include? k}
      UserMailer.notification_email(self.company, self, @updated_attributes).deliver unless @updated_attributes.length.eql?(0)
    end
  end
end
