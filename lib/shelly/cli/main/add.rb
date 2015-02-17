module Shelly
  module CLI
    class Main < Command

      method_option "code-name", :type => :string, :aliases => "-c",
        :desc => "Unique code-name of your cloud"
      method_option :databases, :type => :array, :aliases => "-d",
        :banner => Shelly::App::DATABASE_CHOICES.join(', '),
        :desc => "List of databases of your choice"
      method_option :size, :type => :string, :aliases => "-s",
        :desc => "Server size [large, small]"
      method_option "redeem-code", :type => :string, :aliases => "-r",
        :desc => "Redeem code for free credits"
      method_option "referral-code", :type => :string,
        :desc => "Referral code for additional credit"
      method_option "organization", :type => :string, :aliases => "-o",
        :desc => "Add cloud to existing organization"
      method_option "skip-requirements-check", :type => :boolean,
        :desc => "Skip Shelly Cloud requirements check"
      method_option "zone", :type => :string, :hide => true,
        :desc => "Create cloud in given zone"
      method_option "region", :type => :string,
        :desc => "Create cloud in given region"
      desc "add", "Add a new cloud"
      def add
        check_options(options)
        unless options["skip-requirements-check"]
          return unless check(verbose = false)
        end
        app = Shelly::App.new
        app.code_name = options["code-name"] || ask_for_code_name
        app.databases = options["databases"] || ask_for_databases
        app.size = options["size"] || "small"
        app.organization_name = options["organization"] ||
          ask_for_organization(options)
        if options["zone"].present?
          app.zone = options["zone"]
        else
          app.region = options["region"] || ask_for_region
        end

        app.create
        say "Cloud '#{app}' created in '#{app.organization_name}' organization", :green
        say_new_line

        git_remote = add_remote(app)

        say "Creating Cloudfile", :green
        app.create_cloudfile

        if app.credit > 0 || !app.organization_details_present?
          say_new_line
          say "Billing information", :green
          if app.credit > 0
            say "#{app.credit.to_i} Euro credit remaining."
          end
          if !app.organization_details_present?
            say "Remember to provide billing details before trial ends."
            say app.edit_billing_url
          end
        end

        info_adding_cloudfile_to_repository
        info_deploying_to_shellycloud(git_remote)

      rescue Client::ConflictException => e
        say_error e[:error]
      rescue Client::ValidationException => e
        e.each_error { |error| say_error error, :with_exit => false }
        say_new_line
        say_error "Fix erros in the below command and type it again to create your cloud" , :with_exit => false
        say_error "shelly add --code-name=#{app.code_name.downcase.dasherize} --databases=#{app.databases.join(',')} --organization=#{app.organization_name} --size=#{app.size} --region=#{app.region}"
      rescue Client::ForbiddenException
        say_error "You have to be the owner of '#{app.organization_name}' organization to add clouds"
      rescue Client::NotFoundException => e
        raise unless e.resource == :organization
        say_error "Organization '#{app.organization_name}' not found", :with_exit => false
        say_error "You can list organizations you have access to with `shelly organization list`"
      end

      no_tasks do
        def ask_for_organization(options)
          organizations = Shelly::User.new.organizations

          if organizations.blank?
            ask_for_new_organization(options)
          else
            say "Select organization for this cloud:"
            say_new_line

            loop do
              say "existing organizations:"

              organizations.each do |organization|
                print_wrapped "\u2219 #{organization.name}", :ident => 2
              end

              say green "Or leave empty to create a new organization"
              say_new_line

              selected = ask("Organization:")
              if organizations.select { |o| o.name == selected }.present?
                return selected
              elsif selected.empty?
                say_new_line
                return ask_for_new_organization(options)
              else
                say_new_line
                say_warning "#{selected} organization does not exist"
              end
            end
          end
        end

        def ask_for_new_organization(options = {})
          loop do
            begin
              return create_new_organization(options)
            rescue Client::ValidationException => e
              e.each_error { |error| say_error error, :with_exit => false }
            end
          end
        end

        def ask_for_region
          regions = Shelly::App::REGIONS
          say "Select region for this cloud:"
          say_new_line

          loop do
            say "available regions:"

            regions.each do |region|
              print_wrapped "\u2219 #{region}", :ident => 2
            end
            say_new_line

            selected = ask("Region:").upcase
            if regions.include?(selected)
              return selected
            else
              say_new_line
              say_warning "#{selected} region is not available"
            end
          end
        end
      end
    end
  end
end
