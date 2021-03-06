# encoding: utf-8
require "spec_helper"
require "shelly/cli/main"

describe Shelly::CLI::Main do
  let(:user) { Shelly::User.new }
  before do
    FileUtils.mkpath(File.expand_path("~"))
    FileUtils.stub(:chmod)
    @main = Shelly::CLI::Main.new
    Shelly::CLI::Main.stub(:new).and_return(@main)
    @client = mock
    @client.stub(:authorize!)
    @client.stub(:shellyapp_url).and_return("https://example.com")
    Shelly::Client.stub(:new).and_return(@client)
    Shelly::User.stub(:guess_email).and_return("")
    $stdout.stub(:puts)
    $stdout.stub(:print)
    Shelly::User.stub(:new => user)
  end

  describe "#version" do
    it "should return shelly's version" do
      $stdout.should_receive(:puts).with("shelly version #{Shelly::VERSION}")
      invoke(@main, :version)
    end
  end

  describe "#help" do
    it "should display available commands" do
      out = IO.popen("bin/shelly --debug").read.strip
      out.should include("Tasks:")
      out.should include("shelly add                     # Add a new cloud")
      out.should include("shelly backup <command>        # Manage database backups")
      out.should include("shelly check                   # Check if application fulfills Shelly Cloud requirements")
      out.should include("shelly config <command>        # Manage application configuration files")
      out.should include("shelly console                 # Open application console")
      out.should include("shelly database <command>      # Manage databases")
      out.should include("shelly dbconsole               # Run rails dbconsole")
      out.should include("shelly delete                  # Delete the cloud")
      out.should include("shelly deploy <command>        # View deploy logs")
      out.should include("shelly endpoint <command>      # Manage application HTTP(S) endpoints")
      out.should include("shelly file <command>          # Upload and download files to and from persistent storage")
      out.should include("shelly help [TASK]             # Describe available tasks or one specific task")
      out.should include("shelly info                    # Show basic information about cloud")
      out.should include("shelly list                    # List available clouds")
      out.should include("shelly login [EMAIL]           # Log into Shelly Cloud")
      out.should include("shelly logout                  # Logout from Shelly Cloud")
      out.should include("shelly logs <command>          # View application logs")
      out.should include("shelly maintenance <command>   # Manage application maintenance events")
      out.should include("shelly mongoconsole            # Run MongoDB console")
      out.should include("shelly open                    # Open application page in browser")
      out.should include("shelly organization <command>  # View organizations")
      out.should include("shelly rake TASK               # Run rake task")
      out.should include("shelly redeploy                # Redeploy application")
      out.should include("shelly ssh                     # Log into virtual server")
      out.should include("shelly redis-cli               # Run redis-cli")
      out.should include("shelly register [EMAIL]        # Register new account")
      out.should include("shelly setup                   # Set up git remotes for deployment on Shelly Cloud")
      out.should include("shelly start                   # Start the cloud")
      out.should include("shelly stop                    # Shutdown the cloud")
      out.should include("shelly user <command>          # Manage collaborators")
      out.should include("Options")
      out.should include("[--debug]  # Show debug information")
      out.should include("-h, [--help]   # Describe available tasks or one specific task")
    end

    it "should display help when user is not logged in" do
      out = IO.popen("bin/shelly list --help").read.strip
      out.should include("Usage:")
      out.should include("shelly list")
      out.should include("List available clouds")
      out.should_not include("You are not logged in. To log in use: `shelly login`")
    end
  end

  describe "#register" do
    before do
      @key_path = File.expand_path("~/.ssh/id_rsa.pub")
      FileUtils.mkdir_p("~/.ssh")
      File.open("~/.ssh/id_rsa.pub", "w") { |f| f << "ssh-key AAbbcc" }
      user.stub(:register).with("better@example.com", "secret") { true }
      user.stub(:upload_ssh_key)
    end

    it "should ask for email, password and password confirmation" do
      $stdout.should_receive(:print).with("Email: ")
      $stdout.should_receive(:print).with("Password: ")
      $stdout.should_receive(:print).with("Password confirmation: ")
      fake_stdin(["better@example.com", "secret", "secret", "yes"]) do
        invoke(@main, :register)
      end
    end

    it "should suggest email and use it if user enters blank email" do
      user.should_receive(:register).with("kate@example.com", "secret")
      Shelly::User.stub(:guess_email).and_return("kate@example.com")
      $stdout.should_receive(:print).with("Email (kate@example.com - default): ")
      fake_stdin(["", "secret", "secret", "yes"]) do
        invoke(@main, :register)
      end
    end

    it "should not ask about email if it's provided as argument" do
      user.should_receive(:register).with("kate@example.com", "secret")
      $stdout.should_receive(:puts).with("Registering with email: kate@example.com")
      fake_stdin(["secret", "secret", "yes"]) do
        invoke(@main, :register, "kate@example.com")
      end
    end

    context "when user enters blank email" do
      it "should show error message and exit with 1" do
        Shelly::User.stub(:guess_email).and_return("")
        $stdout.should_receive(:puts).with("\e[31mEmail can't be blank, please try again\e[0m")
        lambda {
          fake_stdin(["", "bob@example.com", "only-pass", "only-pass", "yes"]) do
            invoke(@main, :register)
          end
        }.should raise_error(SystemExit)
      end
    end

    context "on successful registration" do
      it "should display message about registration and email address confirmation" do
        $stdout.should_receive(:puts).with(green "Successfully registered!")
        fake_stdin(["better@example.com", "secret", "secret", "yes"]) do
          invoke(@main, :register)
        end
      end
    end

    context "on unsuccessful registration" do
      it "should display errors and exit with 1" do
        body = {"message" => "Validation Failed", "errors" => [["email", "has been already taken"]]}
        exception = Shelly::Client::ValidationException.new(body)
        user.stub(:register).and_raise(exception)
        $stdout.should_receive(:puts).with("\e[31mEmail has been already taken\e[0m")
        lambda {
          fake_stdin(["better@example.com", "secret", "secret", "yes"]) do
            invoke(@main, :register)
          end
        }.should raise_error(SystemExit)
      end
    end

    context "on rejected Terms of Service" do
      it "should display error and exit with 1" do
        $stdout.should_receive(:puts).with("\e[31mYou must accept the Terms of Service to use Shelly Cloud\e[0m")
        lambda {
          fake_stdin(["kate@example.com", "pass", "pass", "no"]) do
            invoke(@main, :register)
          end
        }.should raise_error(SystemExit)
      end
    end
  end

  shared_examples "login" do
    before do
      Shelly::SshKey.any_instance.stub(:upload => nil, :uploaded? => false)
      FileUtils.mkdir_p("~/.ssh")
      File.open(key_path, "w") { |f| f << "ssh-rsa AAAAB3NzaC1" }
      @main.options = main_options
      @client.stub(:apps).and_return([
          {"code_name" => "abc", "state" => "running",
            "state_description" => "running"},
          {"code_name" => "fooo", "state" => "no_code",
            "state_description" => "turned off (no code pushed)"},])
    end

    context "on successful login" do
      before do
        user.stub(:login).with("megan@example.com", "secret") { true }
      end

      it "should display message about successful login" do
        $stdout.should_receive(:puts).with(green "Login successful")
        fake_stdin(["megan@example.com", "secret"]) do
          invoke(@main, :login)
        end
      end

      it "should accept email as parameter" do
        $stdout.should_receive(:puts).with(green "Login successful")
        fake_stdin(["secret"]) do
          invoke(@main, :login, "megan@example.com")
        end
      end

      it "should accept given path to specific key as parameter" do
        $stdout.should_receive(:puts).with(green "Login successful")
        fake_stdin(["secret"]) do
          invoke(@main, :login, "megan@example.com")
        end
      end

      it "should upload user's public SSH key" do
        Shelly::SshKey.any_instance.should_receive(:upload)
        $stdout.should_receive(:puts).with("Uploading your public SSH key from #{key_path}")
        fake_stdin(["megan@example.com", "secret"]) do
          invoke(@main, :login)
        end
      end

      it "should display list of applications to which user has access" do
        $stdout.should_receive(:puts).with("\e[32mYou have following clouds available:\e[0m")
        $stdout.should_receive(:puts).with(/  abc\s+\|  running/)
        $stdout.should_receive(:puts).with(/  fooo\s+\|  turned off \(no code pushed\)/)
        fake_stdin(["megan@example.com", "secret"]) do
          invoke(@main, :login)
        end
      end

      context "SSH key already uploaded" do
        it "should display message to user" do
          Shelly::SshKey.any_instance.stub(:uploaded? => true)
          $stdout.should_receive(:puts).with("Your SSH key from #{key_path} is already uploaded")
          fake_stdin(["megan@example.com", "secret"]) do
            invoke(@main, :login)
          end
        end
      end

      context "SSH key taken by other user" do
        it "should logout user" do
          body = {"message" => "Validation Failed",
            "errors" => [["fingerprint", "already exists. This SSH key is already in use"]]}
          ex = Shelly::Client::ValidationException.new(body)
          Shelly::SshKey.any_instance.stub(:upload).and_raise(ex)
          user.should_receive(:logout)
          $stdout.should_receive(:puts).with(red "Fingerprint already exists. This SSH key is already in use")
          lambda {
            fake_stdin(["megan@example.com", "secret"]) do
              invoke(@main, :login)
            end
          }.should raise_error(SystemExit)
        end
      end
    end

    context "when local ssh key doesn't exists" do
      it "should display error message and return exit with 1" do
        FileUtils.rm_rf(key_path)
        File.exists?(key_path).should be_false
        $stdout.should_receive(:puts).with("\e[31mNo such file or directory - " + key_path + "\e[0m")
        $stdout.should_receive(:puts).with("\e[31mUse ssh-keygen to generate ssh key pair\e[0m")
        lambda {
          invoke(@main, :login)
        }.should raise_error(SystemExit)
      end
    end

    context "on unauthorized user" do
      it "should exit with 1 and display error message" do
        response = {"message" => "Unauthorized", "error" => "Wrong email or password",
          "url" => "https://admin.winniecloud.com/users/password/new"}
        exception = Shelly::Client::UnauthorizedException.new(response)
        @client.stub(:authorize_with_email_and_password).and_raise(exception)
        $stdout.should_receive(:puts).with("\e[31mWrong email or password\e[0m")
        $stdout.should_receive(:puts).with("\e[31mYou can reset password by using link:\e[0m")
        $stdout.should_receive(:puts).with("\e[31mhttps://admin.winniecloud.com/users/password/new\e[0m")
        lambda {
          fake_stdin(["megan@example.com", "secret"]) do
            invoke(@main, :login)
          end
        }.should raise_error(SystemExit)
      end
    end

    context "on unconfirmed user" do
      it "should exit with 1 and display error message" do
        response = {"message" => "Unauthorized",
          "error" => "Unconfirmed account"}
        exception = Shelly::Client::UnauthorizedException.new(response)
        @client.stub(:authorize_with_email_and_password).and_raise(exception)
        $stdout.should_receive(:puts).with(red "Unconfirmed account")
        lambda {
          fake_stdin(["megan@example.com", "secret"]) do
            invoke(@main, :login)
          end
        }.should raise_error(SystemExit)
      end
    end
  end

  describe "#login" do
    context "with default keys in place" do
      let(:key_path) { File.expand_path("~/.ssh/id_rsa.pub") }
      let(:main_options) { {} }

      it_behaves_like "login"
    end

    context "with given path to specific key" do
      let(:key_path) { File.expand_path("~/.ssh/specific.pub") }
      let(:main_options) { {:key => "~/.ssh/specific.pub"} }

      it_behaves_like "login"
    end
  end

  describe "#add" do
    before do
      FileUtils.mkdir_p("/projects/foo")
      Dir.chdir("/projects/foo")
      @app = Shelly::App.new
      @app.stub(:add_git_remote)
      @app.stub(:create)
      @app.stub(:create_cloudfile)
      @app.stub(:git_url).and_return("git@git.shellycloud.com:foooo.git")
      Shelly::App.stub(:inside_git_repository?).and_return(true)
      Shelly::App.stub(:new).and_return(@app)
      @client.stub(:token).and_return("abc")
      @app.stub(:attributes).and_return(
        {"organization" => {"credit" => 0, "details_present" => true}})
      @app.stub(:git_remote_exist?).and_return(false)
      @main.stub(:check => true)
      @main.stub(:ask_for_organization)
      @main.stub(:ask_for_region).and_return('EU')
    end

    # This spec tests inside_git_repository? hook
    it "should exit with message if command run outside git repository" do
      Shelly::App.stub(:inside_git_repository?).and_return(false)
      $stdout.should_receive(:puts).with("\e[31mCurrent directory is not a git repository.
You need to initialize repository with `git init`.
More info at http://git-scm.com/book/en/Git-Basics-Getting-a-Git-Repository\e[0m")
      lambda {
        fake_stdin(["", ""]) do
          invoke(@main, :add)
        end
      }.should raise_error(SystemExit)
    end

    # This spec tests logged_in? hook
    it "should exit with message if user is not logged in" do
      exception = Shelly::Client::UnauthorizedException.new
      @client.stub(:authorize!).and_raise(exception)
      $stdout.should_receive(:puts).with(red "You are not logged in. To log in use: `shelly login`")
      lambda {
        fake_stdin(["", ""]) do
          invoke(@main, :add)
        end
      }.should raise_error(SystemExit)
    end

    context "command line options" do
      context "invalid params" do
        it "should exit if databases are not valid" do
          $stdout.should_receive(:puts).with("\e[31mTry `shelly help add` for more information\e[0m")
          @main.options = {"code-name" => "foo", "databases" => ["not existing"]}
          lambda {
            invoke(@main, :add)
          }.should raise_error(SystemExit)
        end

        it "should exit if size is not valid" do
          $stdout.should_receive(:puts).with("\e[31mTry `shelly help add` for more information\e[0m")
          @main.options = {"size" => "wrong_size"}
          lambda {
            invoke(@main, :add)
          }.should raise_error(SystemExit)
        end
      end

      context "valid params" do
        it "should create app on shelly cloud" do
          @app.should_receive(:create)
          @main.options = {"code-name" => "foo", "databases" => ["postgresql"], "size" => "large"}
          invoke(@main, :add)
        end

        context "for zone param" do
          it "should use zone from option" do
            @app.should_receive(:zone=).with('zone')
            @main.options = {"zone" => "zone"}
            fake_stdin(["mycodename", ""]) do
              invoke(@main, :add)
            end
          end

          it "should not ask about the region" do
            @app.should_not_receive(:region=)
            $stdout.should_not_receive(:puts).
              with("Select region for this cloud:")
            @main.options = {"zone" => "zone"}
            fake_stdin(["mycodename", ""]) do
              invoke(@main, :add)
            end
          end
        end

        it "should use region from option" do
          @app.should_receive(:region=).with('eu1')
          @main.options = {"region" => "eu1"}
          fake_stdin(["mycodename", ""]) do
            invoke(@main, :add)
          end
        end
      end
    end

    it "should use code name provided by user" do
      $stdout.should_receive(:print).with("Cloud code name (foo - default): ")
      @app.should_receive(:code_name=).with("mycodename")
      fake_stdin(["mycodename", ""]) do
        invoke(@main, :add)
      end
    end

    context "when user provided empty code name" do
      it "should use 'current_dirname' as default" do
        $stdout.should_receive(:print).with("Cloud code name (foo - default): ")
        @app.should_receive(:code_name=).with("foo")
        fake_stdin(["", ""]) do
          invoke(@main, :add)
        end
      end
    end

    it "should use database provided by user (separated by comma or space)" do
      $stdout.should_receive(:print).
        with("Which databases do you want to use " \
             "postgresql, mysql, mongodb, redis, none (postgresql - default): ")
      @app.should_receive(:databases=).with(["postgresql", "mongodb", "redis"])
      fake_stdin(["", "postgresql  ,mongodb redis"]) do
        invoke(@main, :add)
      end
    end

    it "should ask again for databases if unsupported kind typed" do
      $stdout.should_receive(:print).
        with("Which databases do you want to use " \
             "postgresql, mysql, mongodb, redis, none (postgresql - default): ")
      $stdout.should_receive(:print).
        with("Unknown database kind. Supported are: " \
             "postgresql, mysql, mongodb, redis, none: ")
      fake_stdin(["", "postgresql,doesnt-exist", "none"]) do
        invoke(@main, :add)
      end
    end

    context "when user provided empty database" do
      it "should use 'postgresql' database as default" do
        @app.should_receive(:databases=).with(["postgresql"])
        fake_stdin(["", ""]) do
          invoke(@main, :add)
        end
      end
    end

    context "when user provided 'none' database" do
      it "shouldn't take it into account" do
        fake_stdin(["", "postgresql, none"]) do
          invoke(@main, :add)
        end
        @app.databases.should == ['postgresql']
      end
    end

    it "should create the app on shelly cloud" do
      @app.should_receive(:create)
      fake_stdin(["", ""]) do
        invoke(@main, :add)
      end
    end

    it "should create the app on shelly cloud and show credit information" do
      @app.stub(:attributes).and_return(
        "organization" => {"credit" => "40", "details_present" => false})
      @app.stub(:organization_name).and_return("example")
      @app.should_receive(:create)
      $stdout.should_receive(:puts).with(green "Billing information")
      $stdout.should_receive(:puts).with("40 Euro credit remaining.")
      $stdout.should_receive(:puts).with("Remember to provide billing details before trial ends.")
      $stdout.should_receive(:puts).with("https://example.com/organizations/example/edit")

      fake_stdin(["", ""]) do
        invoke(@main, :add)
      end
    end

    it "should create the app on shelly cloud and shouldn't show trial information" do
      @app.should_receive(:create)
      $stdout.should_not_receive(:puts).with(green "Billing information")

      fake_stdin(["", ""]) do
        invoke(@main, :add)
      end
    end

    it "should display validation errors if they are any" do
      body = {"message" => "Validation Failed", "errors" => [["code_name", "has been already taken"]]}
      exception = Shelly::Client::ValidationException.new(body)
      @app.stub(:organization_name).and_return("org-name")
      @app.should_receive(:create).and_raise(exception)
      $stdout.should_receive(:puts).with(red "Code name has been already taken")
      $stdout.should_receive(:puts).with(red "Fix erros in the below command and type it again to create your cloud")
      $stdout.should_receive(:puts).with(red "shelly add --code-name=big-letters --databases=postgresql --organization=org-name --size=small --region=EU")
      lambda {
        fake_stdin(["BiG_LETTERS", ""]) do
          invoke(@main, :add)
        end
      }.should raise_error(SystemExit)
    end

    context "git remote" do
      it "should add one if it doesn't exist" do
        $stdout.should_receive(:puts).with(green "Running: git remote add shelly git@git.shellycloud.com:foooo.git")
        @app.should_receive(:add_git_remote).with("shelly")

        fake_stdin(["foooo", ""]) do
          invoke(@main, :add)
        end
      end

      context "does exist" do
        before do
          @app.stub(:git_remote_exist?).and_return(true)
        end

        it "should ask if one exist and overwrite" do
          $stdout.should_receive(:print).with("Git remote shelly exists, overwrite (yes/no):  ")
          $stdout.should_receive(:puts).with(green "Running: git remote add shelly git@git.shellycloud.com:foooo.git")
          @app.should_receive(:add_git_remote).with("shelly")

          fake_stdin(["foooo", "", "yes"]) do
            invoke(@main, :add)
          end
        end

        it "should ask if one exist and not overwrite" do
          @app.stub(:git_remote_exist?).with('test').and_return(false)
          $stdout.should_receive(:print).with("Git remote shelly exists, overwrite (yes/no):  ")
          $stdout.should_receive(:print).with("Specify remote name: ")
          $stdout.should_receive(:puts).with(green "Running: git remote add test git@git.shellycloud.com:foooo.git")
          $stdout.should_receive(:puts).with("  git push test master")
          @app.should_receive(:add_git_remote).with("test")

          fake_stdin(["foooo", "", "no", "test"]) do
            invoke(@main, :add)
          end
        end
      end
    end

    it "should create Cloudfile" do
      @app.should_receive(:create_cloudfile)
      fake_stdin(["foooo", ""]) { invoke(@main, :add) }
    end

    it "should display info about adding Cloudfile to repository" do
      $stdout.should_receive(:puts).with("\e[32mProject is now configured for use with Shelly Cloud:\e[0m")
      $stdout.should_receive(:puts).with("\e[32mYou can review changes using\e[0m")
      $stdout.should_receive(:puts).with("  git status")
      fake_stdin(["foooo", "none"]) do
        invoke(@main, :add)
      end
    end

    it "should display info on how to deploy to ShellyCloud" do
      $stdout.should_receive(:puts).with("\e[32mWhen you make sure all settings are correct, add changes to your repository:\e[0m")
      $stdout.should_receive(:puts).with("  git add .")
      $stdout.should_receive(:puts).with('  git commit -m "Application added to Shelly Cloud"')
      $stdout.should_receive(:puts).with("\e[32mDeploy to your cloud using:\e[0m")
      $stdout.should_receive(:puts).with("  git push shelly master")
      fake_stdin(["foooo", "none"]) do
        invoke(@main, :add)
      end
    end

    it "should check shelly requirements" do
      $stdout.should_receive(:puts) \
        .with("\e[32mWhen you make sure all settings are correct, add changes to your repository:\e[0m")
      @main.should_receive(:check).with(false).and_return(true)
      fake_stdin(["foooo", "none"]) do
        invoke(@main, :add)
      end
    end

    it "should abort when shelly requirements are not met" do
      $stdout.should_not_receive(:puts) \
        .with("\e[32mWhen you make sure all settings are correct, add changes to your repository:\e[0m")
      @main.should_receive(:check).with(false).and_return(false)
      fake_stdin(["foooo", "none"]) do
        invoke(@main, :add)
      end
    end

    it "should skip checking shelly requirements if --skip-requirements-check provided" do
      @main.options = {"skip-requirements-check" => true}
      @main.should_not_receive(:check)
      fake_stdin(["foooo", "none"]) do
        invoke(@main, :add)
      end
    end

    it "should show forbidden exception" do
      @main.options = {'organization' => "foobar"}
      exception = Shelly::Client::ForbiddenException.new
      @app.should_receive(:create).and_raise(exception)
      $stdout.should_receive(:puts).with(red "You have to be the owner of 'foobar' organization to add clouds")

      expect do
        fake_stdin(["foooo", "none"]) do
          invoke(@main, :add)
        end
      end.to raise_error(SystemExit)
    end

    it "should show conflict exception" do
      exception = Shelly::Client::ConflictException.new({'error' => 'message'})
      @app.should_receive(:create).and_raise(exception)
      $stdout.should_receive(:puts).with(red "message")

      expect do
        fake_stdin(["foo", "none"]) do
          invoke(@main, :add)
        end
      end.to raise_error(SystemExit)
    end

    context "organization" do
      before do
        @main.unstub(:ask_for_organization)
      end

      it "should use --organization option" do
        @main.options = {"organization" => "foo"}
        @app.should_receive(:organization_name=).with("foo")
        fake_stdin(["foo", "none"]) do
          invoke(@main, :add)
        end
      end

      context "ask user for organization" do
        before do
          @client.stub(:organizations).and_return([{"name" => "aaa"}])
        end

        it "should ask user to choose organization" do
          $stdout.should_receive(:puts).
            with("Select organization for this cloud:")
          $stdout.should_receive(:puts).with("  \u2219 aaa")
          $stdout.should_receive(:puts).
            with(green "Or leave empty to create a new organization")
          $stdout.should_receive(:print).with("Organization: ")
          fake_stdin(["foo", "none", "aaa"]) do
            invoke(@main, :add)
          end
        end

        it "should keep asking until user will provide a valid option" do
          $stdout.should_receive(:print).with("Organization: ").twice
          fake_stdin(["foo", "none", "bbb", "aaa"]) do
            invoke(@main, :add)
          end
        end

        it "should use choosen organization" do
          @app.should_receive(:organization_name=).with("aaa")
          fake_stdin(["foo", "none", "aaa"]) do
            invoke(@main, :add)
          end
        end

        it "should ask user to create a new organization" do
          @app.should_receive(:organization_name=).with('org-name')
          @client.should_receive(:create_organization).
            with({:name => "org-name", :redeem_code => nil}, nil)
          $stdout.should_receive(:print).
            with("Organization name (foo - default): ")
          $stdout.should_receive(:puts).
            with(green "Organization 'org-name' created")
          fake_stdin(["foo", "none", "", "org-name"]) do
            invoke(@main, :add)
          end
        end

        it "should use --redeem-code option" do
          @main.options = {'redeem-code' => 'discount'}
          @client.should_receive(:create_organization).
            with({:name => "org-name", :redeem_code => 'discount'}, nil)
          fake_stdin(["foo", "none", "", "org-name"]) do
            invoke(@main, :add)
          end
        end

        it "should use --referral-code option" do
          @main.options = {'referral-code' => 'test'}
          @client.should_receive(:create_organization).
            with({:name => "org-name", :redeem_code=>nil}, 'test')
          fake_stdin(["foo", "none", "", "org-name"]) do
            invoke(@main, :add)
          end
        end
      end

      it "should show that organization was not found" do
        @main.options = {"organization" => "foo"}
        response = {"resource" => "organization"}
        exception = Shelly::Client::NotFoundException.new(response)
        @app.should_receive(:create).and_raise(exception)
        $stdout.should_receive(:puts).
          with(red "Organization 'foo' not found")
        $stdout.should_receive(:puts).
          with(red "You can list organizations you have access to with" \
            " `shelly organization list`")

        expect do
          fake_stdin(["foooo", "none"]) do
            invoke(@main, :add)
          end
        end.to raise_error(SystemExit)
      end
    end

    context "for region" do
      before do
        @main.unstub(:ask_for_region)
      end

      it "should use the value from the --region option" do
        @main.options = {"region" => "EU"}
        @app.should_receive(:region=).with("EU")
        fake_stdin(["foo", "none"]) do
          invoke(@main, :add)
        end
      end

      it "should ask user to choose the region" do
        @app.should_receive(:region=).with("NA")
        $stdout.should_receive(:puts).with("Select region for this cloud:")
        $stdout.should_receive(:puts).with("  \u2219 EU")
        $stdout.should_receive(:puts).with("  \u2219 NA")
        $stdout.should_receive(:print).with("Region (EU - default): ")
        fake_stdin(["foo", "none", "NA"]) do
          invoke(@main, :add)
        end
      end

      context "when given region is not available" do
        it "should print a warning message and ask again" do
          $stdout.should_receive(:puts).
            with(yellow "ASIA region is not available")
          @app.should_not_receive(:region=).with("ASIA")
          @app.should_receive(:region=).with("NA")
          fake_stdin(["foo", "none", "ASIA", "NA"]) do
            invoke(@main, :add)
          end
        end

        context "and empty string was on the input" do
          it "should assign EU region by default" do
            @app.should_receive(:region=).with("EU")
            fake_stdin(["foo", "none", ""]) do
              invoke(@main, :add)
            end
          end
        end
      end

      context "when given region does not accepts new apps" do
        it "should show that it is not available" do
          @main.options = {"region" => "NA"}
          response = {"error" => "Given region is unavailable"}
          exception = Shelly::Client::ConflictException.new(response)
          @app.should_receive(:create).and_raise(exception)
          $stdout.should_receive(:puts).with(red "Given region is unavailable")

          expect do
            fake_stdin(["foo", "none", "NA"]) do
              invoke(@main, :add)
            end
          end.to raise_error(SystemExit)
        end
      end
    end
  end

  describe "#list" do
    before do
      @client.stub(:token).and_return("abc")
      @client.stub(:apps).and_return([
        {"code_name" => "foo", "state" => "running",
          "state_description" => "running",
          "maintenance" => false},
        {"code_name" => "bar", "state" => "deploy_failed",
          "state_description" => "running (last deployment failed)",
          "maintenance" => false},
        {"code_name" => "baz", "state" => "deploy_failed",
          "state_description" => "admin maintenance in progress",
          "maintenance" => true}
      ])
    end

    it "should ensure user has logged in" do
      hooks(@main, :list).should include(:logged_in?)
    end

    it "should display user's clouds" do
      $stdout.should_receive(:puts).with("\e[32mYou have following clouds available:\e[0m")
      $stdout.should_receive(:puts).with(/foo\s+\|  running/)
      $stdout.should_receive(:puts).with(/bar\s+\|  running \(last deployment failed\) \(deployment log: `shelly deploys show last -c bar`\)/)
      $stdout.should_receive(:puts).with(/baz\s+\|  admin maintenance in progress/)
      invoke(@main, :list)
    end

    it "should display info that user has no clouds" do
      @client.stub(:apps).and_return([])
      $stdout.should_receive(:puts).with("\e[32mYou have no clouds yet\e[0m")
      invoke(@main, :list)
    end

    context "#status" do
      it "should ensure user has logged in" do
        hooks(@main, :status).should include(:logged_in?)
      end

      it "should have a 'status' alias" do
        @client.stub(:apps).and_return([])
        $stdout.should_receive(:puts).with("\e[32mYou have no clouds yet\e[0m")
        invoke(@main, :status)
      end
    end
  end

  describe "#start" do
    before do
      setup_project
      @client.stub(:apps).and_return([
          {"code_name" => "foo-production", "state" => "running",
            "state_description" => "running",
            "maintenance" => false},
          {"code_name" => "foo-staging", "state" => "no_code",
            "state_description" => "turned off (no code pushed)",
            "maintenance" => false}])
      @client.stub(:start_cloud => {"deployment" => {"id" => "DEPLOYMENT_ID"}})
      @deployment =  {"messages" => ["message1"],
        "result" => "success", "state" => "finished"}
      @app.stub(:deployment => @deployment)
    end

    it "should ensure user has logged in" do
      hooks(@main, :start).should include(:logged_in?)
    end

    context "single cloud in Cloudfile" do
      it "should start the cloud" do
        $stdout.should_receive(:puts).with(green "Starting cloud foo-production.")
        $stdout.should_receive(:puts).with(green " ---> message1")
        $stdout.should_receive(:puts).with(green "Starting cloud successful")
        invoke(@main, :start)
      end
    end

    # this tests multiple_clouds method used in majority of tasks
    context "without Cloudfile" do
      it "should use cloud from params" do
        Dir.chdir("/projects")
        $stdout.should_receive(:puts).with(green "Starting cloud foo-production.")
        @main.options = {:cloud => "foo-production"}
        invoke(@main, :start)
      end

      it "should ask user to specify cloud, list all clouds and exit" do
        Shelly::App.unstub(:new) # makes Shelly::User#apps work
        Dir.chdir("/projects")
        $stdout.should_receive(:puts).with(red "You have to specify cloud.")
        $stdout.should_receive(:puts).with("Select cloud using `shelly start --cloud CLOUD_NAME`")
        $stdout.should_receive(:puts).with(green "You have following clouds available:")
        $stdout.should_receive(:puts).with("  foo-production  |  running")
        $stdout.should_receive(:puts).with("  foo-staging     |  turned off (no code pushed)")
        lambda { invoke(@main, :start) }.should raise_error(SystemExit)
      end
    end

    # this tests multiple_clouds method used in majority of tasks
    context "multiple clouds in Cloudfile" do
      before do
        Shelly::App.unstub(:new)
        File.open("Cloudfile", 'w') {|f|
          f.write("foo-staging:\nfoo-production:\n") }
      end

      it "should show information to start specific cloud and exit" do
        $stdout.should_receive(:puts).with(red "You have multiple clouds in Cloudfile.")
        $stdout.should_receive(:puts).with("Select cloud using `shelly start --cloud foo-production`")
        $stdout.should_receive(:puts).with("Available clouds:")
        $stdout.should_receive(:puts).with(" * foo-production")
        $stdout.should_receive(:puts).with(" * foo-staging")
        lambda { invoke(@main, :start) }.should raise_error(SystemExit)
      end

      it "should fetch from command line which cloud to start" do
        @client.should_receive(:start_cloud).with("foo-staging")
        @client.should_receive(:deployment).
          with("foo-staging", "DEPLOYMENT_ID").and_return(@deployment)
        $stdout.should_receive(:puts).with(green "Starting cloud foo-staging.")
        $stdout.should_receive(:puts).with(green " ---> message1")
        $stdout.should_receive(:puts).with(green "Starting cloud successful")
        @main.options = {:cloud => "foo-staging"}
        invoke(@main, :start)
      end
    end

    context "on failure" do
      it "should show information that cloud is running" do
        raise_conflict("state" => "running")
        $stdout.should_receive(:puts).with(red "Not starting: cloud 'foo-production' is already running")
        lambda { invoke(@main, :start)  }.should raise_error(SystemExit)
      end

      it "should show information that cloud is deploying" do
        raise_conflict("state" => "deploying")
        $stdout.should_receive(:puts).with(red "Not starting: cloud 'foo-production' is currently deploying")
        lambda { invoke(@main, :start) }.should raise_error(SystemExit)
      end

      it "should show information that cloud has no code" do
        @app.stub(:git_remote_name).and_return('shelly')
        raise_conflict("state" => "no_code")
        $stdout.should_receive(:puts).with(red "Not starting: no source code provided")
        $stdout.should_receive(:puts).with(red "Push source code using:")
        $stdout.should_receive(:puts).with("`git push shelly master`")
        lambda { invoke(@main, :start) }.should raise_error(SystemExit)
      end

      it "should show information that cloud is in deploy_failed state" do
        raise_conflict("state" => "deploy_failed")
        $stdout.should_receive(:puts).with(red "Not starting: deployment failed")
        $stdout.should_receive(:puts).with(red "Support has been notified")
        $stdout.should_receive(:puts).
          with(red "Check `shelly deploys show last --cloud foo-production` for reasons of failure")
        lambda { invoke(@main, :start) }.should raise_error(SystemExit)
      end

      it "should show that winnie is out of resources" do
        raise_conflict("state" => "not_enough_resources")
        $stdout.should_receive(:puts).with(red "Sorry, There are no resources for your servers.
We have been notified about it. We will be adding new resources shortly")
        lambda { invoke(@main, :start) }.should raise_error(SystemExit)
      end

      it "should show messages about billing" do
        raise_conflict("state" => "no_billing")
        @app.stub(:edit_billing_url).and_return("http://example.com/billing/edit")
        $stdout.should_receive(:puts).with(red "Please fill in billing details to start foo-production.")
        $stdout.should_receive(:puts).with(red "Visit: http://example.com/billing/edit")
        lambda { invoke(@main, :start) }.should raise_error(SystemExit)
      end

      it "should show messge about app turning off" do
        raise_conflict("state" => "turning_off")
        $stdout.should_receive(:puts).with(red "Not starting: cloud 'foo-production' is turning off.
Wait until cloud is in 'turned off' state and try again.")
        lambda { invoke(@main, :start) }.should raise_error(SystemExit)
      end

      it "should show message about blocked deploy" do
        exception = Shelly::Client::LockedException.new("message" => "reason of block")
        @client.should_receive(:start_cloud).with("foo-production").and_raise(exception)
        $stdout.should_receive(:puts).with(red "Deployment is currently blocked:")
        $stdout.should_receive(:puts).with(red "reason of block")
        lambda { invoke(@main, :start) }.should raise_error(SystemExit)
      end

      def raise_conflict(options = {})
        body = {"state" => "no_code"}.merge(options)
        exception = Shelly::Client::ConflictException.new(body)
        @client.stub(:start_cloud).and_raise(exception)
      end
    end
  end

  describe "#stop" do
    before do
      @user = Shelly::User.new
      @client.stub(:token).and_return("abc")
      FileUtils.mkdir_p("/projects/foo")
      Dir.chdir("/projects/foo")
      File.open("Cloudfile", 'w') {|f| f.write("foo-production:\n") }
      Shelly::User.stub(:new).and_return(@user)
      @client.stub(:apps).and_return([{"code_name" => "foo-production"}, {"code_name" => "foo-staging"}])
      @app = Shelly::App.new("foo-production")
      Shelly::App.stub(:new).and_return(@app)
      @client.stub(:stop_cloud => {"deployment" => {"id" => "DEPLOYMENT_ID"}})
      @app.stub(:deployment => {"messages" => ["message1"],
        "result" => "success", "state" => "finished"})
    end

    it "should ensure user has logged in" do
      hooks(@main, :stop).should include(:logged_in?)
    end

    # multiple_clouds is tested in main_spec.rb in describe "#start" block
    it "should ensure multiple_clouds check" do
      @main.should_receive(:multiple_clouds).and_return(@app)
      fake_stdin(["yes"]) do
        invoke(@main, :stop)
      end
    end

    it "should stop the cloud" do
      $stdout.should_receive(:print).with("Are you sure you want to shut down 'foo-production' cloud (yes/no): ")
      $stdout.should_receive(:puts).with("\n")
      $stdout.should_receive(:puts).with(green " ---> message1")
      $stdout.should_receive(:puts).with(green "Stopping cloud successful")
      fake_stdin(["yes"]) do
        invoke(@main, :stop)
      end
    end

    context "on failure" do
      context "when application is in deploy_failed state" do
        it "should display error and `shelly deploy show last --cloud foo-production` command" do
          @app.stub(:deployment => {"messages" => ["message1"],
            "result" => "failure", "state" => "deploy_failed"})

          $stdout.should_receive(:puts).with(green " ---> message1")
          $stdout.should_receive(:puts).
            with(red "Stopping cloud failed. See logs with `shelly deploy show last --cloud foo-production`")
          fake_stdin(["yes"]) do
            invoke(@main, :stop)
          end
        end
      end

      it "should exit if user doesn't have access to clouds in Cloudfile" do
        @client.stub(:stop_cloud).and_raise(Shelly::Client::NotFoundException.new("resource" => "cloud"))
        $stdout.should_receive(:puts).with(red "You have no access to 'foo-production' cloud defined in Cloudfile")
        lambda {
          fake_stdin(["yes"]) do
            invoke(@main, :stop)
          end
        }.should raise_error(SystemExit)
      end

      it "should show messages about app being deployed" do
        raise_conflict("state" => "deploying")
        $stdout.should_receive(:puts).with(red "Your cloud is currently being deployed and it can not be stopped.")
        lambda do
          fake_stdin(["yes"]) do
            invoke(@main, :stop)
          end
        end.should raise_error(SystemExit)
      end

      it "should show messge about app's no_code" do
        raise_conflict("state" => "no_code")
        $stdout.should_receive(:puts).with(red "You need to deploy your cloud first.")
        $stdout.should_receive(:puts).with('More information can be found at:')
        $stdout.should_receive(:puts).with('https://example.com/documentation/deployment')
        lambda do
          fake_stdin(["yes"]) do
            invoke(@main, :stop)
          end
        end.should raise_error(SystemExit)
      end

      it "should show messge about app turning off" do
        raise_conflict("state" => "turning_off")
        $stdout.should_receive(:puts).with(red "Your cloud is turning off.")
        lambda do
          fake_stdin(["yes"]) do
            invoke(@main, :stop)
          end
        end.should raise_error(SystemExit)
      end

      def raise_conflict(options = {})
        body = {"state" => "no_code"}.merge(options)
        exception = Shelly::Client::ConflictException.new(body)
        @client.stub(:stop_cloud).and_raise(exception)
      end
    end
  end

  describe "#info" do
    before do
      File.open("Cloudfile", 'w') { |f| f.write("foo-production:\n") }
      @app = Shelly::App.new("foo-production")
      @main.stub(:logged_in?).and_return(true)
      @app.stub(:attributes).and_return(response)
      @statistics = [{"name" => "app1",
                      "memory" => {"kilobyte" => "276756", "percent" => "74.1"},
                      "swap" => {"kilobyte" => "44332", "percent" => "2.8"},
                      "cpu" => {"wait" => "0.8", "system" => "0.0", "user" => "0.1"},
                      "load" => {"avg15" => "0.13", "avg05" => "0.15", "avg01" => "0.04"}}]
      @app.stub(:statistics).and_return(@statistics)
    end

    it "should ensure user has logged in" do
      hooks(@main, :info).should include(:logged_in?)
    end

    # multiple_clouds is tested in main_spec.rb in describe "#start" block
    it "should ensure multiple_clouds check" do
      @main.should_receive(:multiple_clouds).and_return(@app)
      invoke(@main, :info)
    end

    context "on success" do
      it "should display basic information about cloud" do
        @main.should_receive(:multiple_clouds).and_return(@app)
        $stdout.should_receive(:puts).with(green "Cloud foo-production:")
        $stdout.should_receive(:puts).with("  Region: EU")
        $stdout.should_receive(:puts).with("  State: running")
        $stdout.should_receive(:puts).with("  Deployed commit sha: 52e65ed2d085eaae560cdb81b2b56a7d76")
        $stdout.should_receive(:puts).with("  Deployed commit message: Commit message")
        $stdout.should_receive(:puts).with("  Deployed by: megan@example.com")
        $stdout.should_receive(:puts).with("  Repository URL: git@winniecloud.net:example-cloud")
        $stdout.should_receive(:puts).with("  Web server IP: 22.22.22.22")
        $stdout.should_receive(:puts).with("  Statistics:")
        $stdout.should_receive(:puts).with("    app1:")
        $stdout.should_receive(:puts).with("      Load average: 1m: 0.04, 5m: 0.15, 15m: 0.13")
        $stdout.should_receive(:puts).with("      CPU: 0.8%, MEM: 74.1%, SWAP: 2.8%")
        $stdout.should_receive(:puts).with("  Usage:")
        $stdout.should_receive(:puts).with("    Filesystem:")
        $stdout.should_receive(:puts).with("      Current: 2.04 GiB")
        $stdout.should_receive(:puts).with("      Average: 182.39 MiB")
        $stdout.should_receive(:puts).with("    Database:")
        $stdout.should_receive(:puts).with("      Current: 1.19 MiB")
        $stdout.should_receive(:puts).with("      Average: 18.24 MiB")
        $stdout.should_receive(:puts).with("    Traffic:")
        $stdout.should_receive(:puts).with("      Incoming: 11.54 GiB")
        $stdout.should_receive(:puts).with("      Outgoing: 1.15 GiB")
        $stdout.should_receive(:puts).with("      Total: 12.69 GiB")
        invoke(@main, :info)
      end

      context "when usage and traffic is not present" do
        before do
          @app.stub(:attributes).and_return(response({
            "billing" => {
              "current_month_costs" => {
                "usage" => [],
                "traffic" => {
                  "incoming"   => nil,
                  "outgoing"   => nil,
                  "total"      => nil
                }
              }
            },
          }))
        end

        it "should print 0.0 B usage" do
          @main.should_receive(:multiple_clouds).and_return(@app)
          $stdout.should_receive(:puts).with("  Usage:")
          $stdout.should_not_receive(:puts).with("    Filesystem:")
          $stdout.should_not_receive(:puts).with("    Database:")
          $stdout.should_receive(:puts).with("    Traffic:")
          $stdout.should_receive(:puts).with("      Incoming: 0.0 B")
          $stdout.should_receive(:puts).with("      Outgoing: 0.0 B")
          $stdout.should_receive(:puts).with("      Total: 0.0 B")
          invoke(@main, :info)
        end
      end

      context "when deploy failed" do
        context "and app is in maintenance" do
          it "should display basic information without instruction to show last app logs" do
            @app.stub(:attributes).
              and_return(response({"state" => "deploy_failed",
                         "state_description" => "admin maintenance in progress",
                         "maintenance" => true}))
            @main.should_receive(:multiple_clouds).and_return(@app)
            $stdout.should_receive(:puts).with(red "Cloud foo-production:")
            $stdout.should_receive(:puts).with("  Region: EU")
            $stdout.should_receive(:puts).with("  State: admin maintenance in progress")
            $stdout.should_receive(:puts).with("  Deployed commit sha: 52e65ed2d085eaae560cdb81b2b56a7d76")
            $stdout.should_receive(:puts).with("  Deployed commit message: Commit message")
            $stdout.should_receive(:puts).with("  Deployed by: megan@example.com")
            $stdout.should_receive(:puts).with("  Repository URL: git@winniecloud.net:example-cloud")
            $stdout.should_receive(:puts).with("  Web server IP: 22.22.22.22")
            $stdout.should_receive(:puts).with("  Statistics:")
            $stdout.should_receive(:puts).with("    app1:")
            $stdout.should_receive(:puts).with("      Load average: 1m: 0.04, 5m: 0.15, 15m: 0.13")
            $stdout.should_receive(:puts).with("      CPU: 0.8%, MEM: 74.1%, SWAP: 2.8%")
            $stdout.should_receive(:puts).with("  Usage:")
            $stdout.should_receive(:puts).with("    Filesystem:")
            $stdout.should_receive(:puts).with("      Current: 2.04 GiB")
            $stdout.should_receive(:puts).with("      Average: 182.39 MiB")
            $stdout.should_receive(:puts).with("    Database:")
            $stdout.should_receive(:puts).with("      Current: 1.19 MiB")
            $stdout.should_receive(:puts).with("      Average: 18.24 MiB")
            $stdout.should_receive(:puts).with("    Traffic:")
            $stdout.should_receive(:puts).with("      Incoming: 11.54 GiB")
            $stdout.should_receive(:puts).with("      Outgoing: 1.15 GiB")
            $stdout.should_receive(:puts).with("      Total: 12.69 GiB")
            invoke(@main, :info)
          end
        end

        context "and app is not in maintenance" do
          it "should display basic information and instruction to show last app logs" do
            @app.stub(:attributes).
              and_return(response({"state" => "deploy_failed",
                         "state_description" => "running (last deployment failed)",
                         "maintenance" => false}))
            @main.should_receive(:multiple_clouds).and_return(@app)
            $stdout.should_receive(:puts).with(red "Cloud foo-production:")
            $stdout.should_receive(:puts).with("  Region: EU")
            $stdout.should_receive(:puts).with("  State: running (last deployment failed) (deployment log: `shelly deploys show last -c foo-production`)")
            $stdout.should_receive(:puts).with("  Deployed commit sha: 52e65ed2d085eaae560cdb81b2b56a7d76")
            $stdout.should_receive(:puts).with("  Deployed commit message: Commit message")
            $stdout.should_receive(:puts).with("  Deployed by: megan@example.com")
            $stdout.should_receive(:puts).with("  Repository URL: git@winniecloud.net:example-cloud")
            $stdout.should_receive(:puts).with("  Web server IP: 22.22.22.22")
            $stdout.should_receive(:puts).with("  Statistics:")
            $stdout.should_receive(:puts).with("    app1:")
            $stdout.should_receive(:puts).with("      Load average: 1m: 0.04, 5m: 0.15, 15m: 0.13")
            $stdout.should_receive(:puts).with("      CPU: 0.8%, MEM: 74.1%, SWAP: 2.8%")
            $stdout.should_receive(:puts).with("  Usage:")
            $stdout.should_receive(:puts).with("    Filesystem:")
            $stdout.should_receive(:puts).with("      Current: 2.04 GiB")
            $stdout.should_receive(:puts).with("      Average: 182.39 MiB")
            $stdout.should_receive(:puts).with("    Database:")
            $stdout.should_receive(:puts).with("      Current: 1.19 MiB")
            $stdout.should_receive(:puts).with("      Average: 18.24 MiB")
            $stdout.should_receive(:puts).with("    Traffic:")
            $stdout.should_receive(:puts).with("      Incoming: 11.54 GiB")
            $stdout.should_receive(:puts).with("      Outgoing: 1.15 GiB")
            $stdout.should_receive(:puts).with("      Total: 12.69 GiB")
            invoke(@main, :info)
          end
        end

        it "should not display statistics when statistics are empty" do
          @app.stub(:attributes).and_return(response({"state" => "turned_off", "state_description" => "turned off"}))
          @main.should_receive(:multiple_clouds).and_return(@app)
          @app.stub(:statistics).and_return([])
          $stdout.should_not_receive(:puts).with("Statistics:")
          invoke(@main, :info)
        end
      end

      context "on failure" do
        it "should raise an error if statistics unavailable" do
          @main.should_receive(:multiple_clouds).and_return(@app)
          exception = Shelly::Client::GatewayTimeoutException.new
          @app.stub(:statistics).and_raise(exception)
          $stdout.should_receive(:puts).with(red "Server statistics temporarily unavailable")
          lambda { invoke(@main, :info) }.should raise_error(SystemExit)
        end
      end
    end

    def response(options = {})
      { "code_name" => "foo-production",
        "region" => "EU",
        "state" => "running",
        "state_description" => "running",
        "git_info" => {
          "deployed_commit_message" => "Commit message",
          "deployed_commit_sha" => "52e65ed2d085eaae560cdb81b2b56a7d76",
          "repository_url" => "git@winniecloud.net:example-cloud",
          "deployed_push_author" => "megan@example.com"
        },
        "billing" => {
          "current_month_costs" => {
            "usage" => [
              {
                "kind"    => "filesystem",
                "avg"     => 191248000,
                "current" => 2191248000
              }, {
                "kind"     => "database",
                "avg"      => 19128000,
                "current"  => 1248000
              }
            ],
            "traffic" => {
              "incoming"   => 12391283291,
              "outgoing"   => 1239123843,
              "total"      => 12391283291 + 1239123843
            }
          }
        },
        "web_server_ip" => ["22.22.22.22"]}.merge(options)
    end
  end

  describe "#setup" do
    before do
      Shelly::App.stub(:inside_git_repository?).and_return(true)
      @client.stub(:token).and_return("abc")
      @client.stub(:app).and_return("git_info" => {"repository_url" => "git_url"})
      @app = Shelly::App.new("foo-staging")
      @app.stub(:git_remote_exist?).and_return(false)
      @app.stub(:system)
      Shelly::App.stub(:new).and_return(@app)
      File.open("Cloudfile", 'w') {|f| f.write("foo-staging:\n") }
    end

    it "should ensure user has logged in" do
      hooks(@main, :setup).should include(:logged_in?)
    end

    it "should ensure that user is inside git repo" do
      hooks(@main, :setup).should include(:inside_git_repository?)
    end

    # multiple_clouds is tested in main_spec.rb in describe "#start" block
    it "should ensure multiple_clouds check" do
      @main.should_receive(:multiple_clouds).and_return(@app)
      invoke(@main, :setup)
    end

    it "should show info about adding remote and fetching changes" do
      $stdout.should_receive(:puts).with(green "Setting up foo-staging cloud")
      $stdout.should_receive(:puts).with("Running: git remote add shelly git_url")
      $stdout.should_receive(:puts).with("Running: git fetch shelly")
      $stdout.should_receive(:puts).with(green "Your application is set up.")
      invoke(@main, :setup)
    end

    it "should add git remote" do
      @app.should_receive(:add_git_remote)
      invoke(@main, :setup)
    end

    it "should fetch remote" do
      @app.should_receive(:git_fetch_remote)
      invoke(@main, :setup)
    end

    context "when remote exists" do
      before do
        @app.stub(:git_remote_exist?).and_return(true)
      end

      context "and user answers yes" do
        it "should overwrite remote" do
          @app.should_receive(:add_git_remote)
          @app.should_receive(:git_fetch_remote)
          fake_stdin(["yes"]) do
            invoke(@main, :setup)
          end
        end

        it "should show info about adding default remote and fetching changes" do
          $stdout.should_receive(:puts).with(green "Setting up foo-staging cloud")
          $stdout.should_receive(:puts).with("Running: git remote add shelly git_url")
          $stdout.should_receive(:puts).with("Running: git fetch shelly")
          $stdout.should_receive(:puts).with(green "Your application is set up.")
          fake_stdin(["yes"]) do
            invoke(@main, :setup)
          end
        end
      end

      context "and user answers no" do
        before do
          @app.stub(:git_remote_exist?).with('remote').and_return(false)
        end

        it "should display commands to perform manually" do
          $stdout.should_receive(:print).with("Specify remote name: ")
          @app.should_receive(:add_git_remote).with('remote')
          @app.should_receive(:git_fetch_remote).with('remote')
          fake_stdin(["no", "remote"]) do
            invoke(@main, :setup)
          end
        end

        it "should show info about adding custom remote and fetching changes" do
          $stdout.should_receive(:puts).with(green "Setting up foo-staging cloud")
          $stdout.should_receive(:print).with("Specify remote name: ")
          $stdout.should_receive(:puts).with("Running: git remote add remote git_url")
          $stdout.should_receive(:puts).with("Running: git fetch remote")
          $stdout.should_receive(:puts).with(green "Your application is set up.")
          fake_stdin(["no", "remote"]) do
            invoke(@main, :setup)
          end
        end
      end
    end
  end

  describe "#delete" do
    before  do
      Shelly::App.stub(:inside_git_repository?).and_return(true)
      @user = Shelly::User.new
      @app = Shelly::App.new('foo-staging')
      @client.stub(:token).and_return("abc")
      @app.stub(:delete)
      Shelly::User.stub(:new).and_return(@user)
      Shelly::App.stub(:new).and_return(@app)
      @client.stub(:app).and_return("git_info" => {"repository_url" => "git_url"})
    end

    it "should ensure user has logged in" do
      hooks(@main, :delete).should include(:logged_in?)
    end

    # multiple_clouds is tested in main_spec.rb in describe "#start" block
    it "should ensure multiple_clouds check" do
      @client.stub(:delete)
      @main.should_receive(:multiple_clouds).and_return(@app)
      fake_stdin(["foo-staging"]) do
        invoke(@main, :delete)
      end
    end

    context "when cloud is given" do
      before do
        File.open("Cloudfile", 'w') {|f|
          f.write("foo-staging:\nfoo-production:\n") }
      end

      it "should display warning and ask about deleting the application" do
        $stdout.should_receive(:puts).with("You are going to:")
        $stdout.should_receive(:puts).
          with(" * remove all files stored in the persistent storage for" \
               " foo-staging,")
        $stdout.should_receive(:puts).
          with(" * remove all database data for foo-staging,")
        $stdout.should_receive(:puts).
          with(" * remove foo-staging cloud from Shelly Cloud")
        $stdout.should_receive(:puts).with("\n")
        $stdout.should_receive(:puts).
          with(red "This action is permanent and can not be undone.")
        $stdout.should_receive(:puts).with("\n")
        $stdout.should_receive(:print).
          with("Please confirm with the name of the cloud: ")
        $stdout.should_receive(:puts).with("Scheduling application delete - done")
        $stdout.should_receive(:puts).with("Removing git remote - done")
        @main.options = {:cloud => "foo-staging"}
        fake_stdin(["foo-staging"]) do
          invoke(@main, :delete)
        end
      end

      context 'when given code name does not match' do
        it "should print message and return exit 1" do
          @app.should_not_receive(:delete)
          $stdout.should_receive(:puts).
            with(red "The name does not match. Operation aborted.")
          lambda{
            fake_stdin(["foo-production"]) do
              @main.options = {:cloud => "foo-staging"}
              invoke(@main, :delete)
            end
          }.should raise_error(SystemExit)
        end
      end

      it "should remove git remote" do
        @app.should_receive(:remove_git_remote)
        @main.options = {:cloud => "foo-staging"}
        fake_stdin(["foo-staging"]) do
          invoke(@main, :delete)
        end
      end
    end

    context "when git repository doesn't exist" do
      before do
        File.open("Cloudfile", 'w') {|f|
          f.write("foo-staging:\n") }
      end

      it "should say that Git remote missing" do
        Shelly::App.stub(:inside_git_repository?).and_return(false)
        $stdout.should_receive(:puts).with("Missing git remote")
        fake_stdin(["foo-staging"]) do
          @main.options = {:cloud => "foo-staging"}
          invoke(@main, :delete)
        end
      end
    end

    context "when no cloud option is given" do
      before do
        File.open("Cloudfile", 'w') {|f|
          f.write("foo-staging:\n") }
      end

      it "should take the cloud from Cloudfile" do
        $stdout.should_receive(:puts).with("You are going to:")
        $stdout.should_receive(:puts).
          with(" * remove all files stored in the persistent storage for" \
               " foo-staging,")
        $stdout.should_receive(:puts).
          with(" * remove all database data for foo-staging,")
        $stdout.should_receive(:puts).
          with(" * remove foo-staging cloud from Shelly Cloud")
        $stdout.should_receive(:puts).with("\n")
        $stdout.should_receive(:puts).
          with(red "This action is permanent and can not be undone.")
        $stdout.should_receive(:puts).with("\n")
        $stdout.should_receive(:print).
          with("Please confirm with the name of the cloud: ")
        $stdout.should_receive(:puts).with("Scheduling application delete - done")
        $stdout.should_receive(:puts).with("Removing git remote - done")
        fake_stdin(["foo-staging"]) do
          invoke(@main, :delete)
        end
      end
    end
  end

  describe "#logout" do
    before do
      user.stub(:logout => true)
      user.stub(:delete_ssh_key => false)
    end

    it "should ensure user has logged in" do
      hooks(@main, :logout).should include(:logged_in?)
    end

    it "should logout from shelly cloud and show message" do
      $stdout.should_receive(:puts).with("You have been successfully logged out")
      user.should_receive(:logout)
      invoke(@main, :logout)
    end

    it "should notify user that ssh key was removed" do
      user.ssh_keys.stub(:destroy => true)
      $stdout.should_receive(:puts).with("Your public SSH key has been removed from Shelly Cloud")
      user.ssh_keys.should_receive(:destroy)
      invoke(@main, :logout)
    end

    context "option key" do
      it "should be removed" do
        sshkey = mock
        Shelly::SshKey.should_receive(:new).with('path/sshkey.pub').and_return(sshkey)
        $stdout.should_receive(:puts).with("Your public SSH key has been removed from Shelly Cloud")
        sshkey.should_receive(:destroy).and_return(true)
        @main.options = {:key => "path/sshkey.pub"}
        invoke(@main, :logout)
      end
    end
  end

  describe "#rake" do
    before do
      setup_project
      @main.stub(:rake_args).and_return(%w(db:migrate))
    end

    it "should ensure user has logged in" do
      hooks(@main, :rake).should include(:logged_in?)
    end

    # multiple_clouds is tested in main_spec.rb in describe "#start" block
    it "should ensure multiple_clouds check" do
      @app.stub(:rake)
      @main.should_receive(:multiple_clouds).and_return(@app)
      invoke(@main, :rake, "db:migrate")
    end

    it "should invoke rake task" do
      @app.should_receive(:rake).with("db:migrate", nil)
      invoke(@main, :rake, "db:migrate")
    end

    describe "#rake_args" do
      before { @main.unstub!(:rake_args) }

      it "should return Array of rake arguments (skipping shelly gem arguments)" do
        argv = %w(rake -T db --server app1 --cloud foo-production --debug)
        @main.rake_args(argv).should == %w(-T db)
      end

      it "should take ARGV as default default argument" do
        # Rather poor, I test if method without args returns the same as method with ARGV
        @main.rake_args.should == @main.rake_args(ARGV)
      end
    end
  end

  describe "#redeploy" do
    before do
      setup_project
      @client.stub(:redeploy => {"deployment" => {"id" => "DEPLOYMENT_ID"}})
      @app.stub(:deployment => {"messages" => ["message1"],
        "result" => "success", "state" => "finished"})
    end

    # multiple_clouds is tested in main_spec.rb in describe "#start" block
    it "should ensure multiple_clouds check" do
      @main.should_receive(:multiple_clouds).and_return(@app)
      invoke(@main, :redeploy)
    end

    it "should redeploy the application" do
      $stdout.should_receive(:puts).with(green "Redeploying your application for cloud 'foo-production'")
      @app.should_receive(:redeploy)
      invoke(@main, :redeploy)
    end

    it "should print deployment messages" do
      $stdout.should_receive(:puts).with(green " ---> message1")
      $stdout.should_receive(:puts).with(green "Cloud redeploy successful")
      invoke(@main, :redeploy)
    end

    context "on redeploy failure" do
      context "when application is in deploy_failed state" do
        it "should display error and `shelly deploy show last --cloud foo-production` command" do
          @app.stub(:deployment => {"messages" => ["message1"],
            "result" => "failure", "state" => "deploy_failed"})
          $stdout.should_receive(:puts).with(green " ---> message1")
          $stdout.should_receive(:puts).
            with(red "Cloud redeploy failed. See logs with `shelly deploy show last --cloud foo-production`")
          invoke(@main, :redeploy)
        end
      end

      context "when application is in deploying state" do
        it "should display error that deploy is in progress" do
          exception = Shelly::Client::ConflictException.new("state" => "deploying")
          @client.should_receive(:redeploy).with("foo-production").and_raise(exception)
          $stdout.should_receive(:puts).with(red "Your application is being redeployed at the moment")
          lambda {
            invoke(@main, :redeploy)
          }.should raise_error(SystemExit)
        end
      end

      %w(no_code no_billing turned_off).each do |state|
        context "when application is in #{state} state" do
          it "should display error that cloud is not running" do
            exception = Shelly::Client::ConflictException.new("state" => state)
            @client.should_receive(:redeploy).with("foo-production").and_raise(exception)
            $stdout.should_receive(:puts).with(red "Cloud foo-production is not running")
            $stdout.should_receive(:puts).with("Start your cloud with `shelly start --cloud foo-production`")
            lambda {
              invoke(@main, :redeploy)
            }.should raise_error(SystemExit)
          end
        end
      end

      context "when deployment is blocked" do
        it "should display reason of the block" do
          exception = Shelly::Client::LockedException.new("message" => "reason of block")
          @client.should_receive(:redeploy).with("foo-production").and_raise(exception)
          $stdout.should_receive(:puts).with(red "Deployment is currently blocked:")
          $stdout.should_receive(:puts).with(red "reason of block")
          lambda {
            invoke(@main, :redeploy)
          }.should raise_error(SystemExit)
        end
      end

      it "should re-raise exception on unknown state" do
        exception = Shelly::Client::ConflictException.new("state" => "doing_something")
        @client.should_receive(:redeploy).with("foo-production").and_raise(exception)
        lambda {
          invoke(@main, :redeploy)
        }.should raise_error(Shelly::Client::ConflictException)
      end
    end
  end

  describe "#open" do
    before do
      setup_project
      @app.stub(:open)
    end

    # multiple_clouds is tested in main_spec.rb in describe "#start" block
    it "should ensure multiple_clouds check" do
      @client.stub(:open)
      @main.should_receive(:multiple_clouds).and_return(@app)
      invoke(@main, :open)
    end

    it "should open app" do
      @app.should_receive(:open)
      invoke(@main, :open)
    end
  end

  describe "#console" do
    before do
      setup_project
    end

    it "should ensure user has logged in" do
      hooks(@main, :console).should include(:logged_in?)
    end

    it "execute ssh command" do
      @app.should_receive(:console)
      invoke(@main, :console)
    end

    context "virtual servers are not running" do
      it "should display error" do
        @client.stub(:tunnel).and_raise(Shelly::Client::ConflictException)
        $stdout.should_receive(:puts).with(red "Cloud foo-production is not running. Cannot run console.")
        lambda {
          invoke(@main, :console)
        }.should raise_error(SystemExit)
      end
    end

    context "virtual server not found" do
      it "should display error" do
        ex = Shelly::Client::NotFoundException.new("resource" => "virtual_server")
        @client.stub(:tunnel).and_raise(ex)
        @main.options = {:server => "foobar"}
        $stdout.should_receive(:puts).with(red "Virtual server 'foobar' not found or not configured for running console")
        lambda {
          invoke(@main, :console)
        }.should raise_error(SystemExit)
      end
    end
  end

  describe "#dbconsole" do
    before do
      setup_project
    end

    it "should ensure user has logged in" do
      hooks(@main, :dbconsole).should include(:logged_in?)
    end

    it "should execute ssh command" do
      @app.should_receive(:dbconsole)
      invoke(@main, :dbconsole)
    end

    context "Instances are not running" do
      it "should display error" do
        @client.stub(:configured_db_server).and_raise(Shelly::Client::ConflictException)
        $stdout.should_receive(:puts).with(red "Cloud foo-production wasn't deployed properly. Can not run dbconsole.")
        lambda {
          invoke(@main, :dbconsole)
        }.should raise_error(SystemExit)
      end
    end
  end

  describe "#mongoconsole" do
    before do
      setup_project
    end

    it "should ensure user has logged in" do
      hooks(@main, :mongoconsole).should include(:logged_in?)
    end

    it "should execute ssh command" do
      @app.should_receive(:mongoconsole)
      invoke(@main, :mongoconsole)
    end

    context "Instances are not running" do
      it "should display error" do
        @client.stub(:configured_db_server).and_raise(Shelly::Client::ConflictException)
        $stdout.should_receive(:puts).with(red "Cloud foo-production wasn't deployed properly. Can not run MongoDB console.")
        lambda {
          invoke(@main, :mongoconsole)
        }.should raise_error(SystemExit)
      end
    end
  end

  describe "#redis_cli" do
    before do
      setup_project
    end

    it "should ensure user has logged in" do
      hooks(@main, :redis_cli).should include(:logged_in?)
    end

    it "should execute ssh command" do
      @app.should_receive(:redis_cli)
      invoke(@main, :redis_cli)
    end

    context "Instances are not running" do
      it "should display error" do
        @client.stub(:configured_db_server).and_raise(Shelly::Client::ConflictException)
        $stdout.should_receive(:puts).with(red "Cloud foo-production wasn't deployed properly. Can not run redis-cli.")
        lambda {
          invoke(@main, :redis_cli)
        }.should raise_error(SystemExit)
      end
    end
  end

  describe "#ssh" do
    before do
      setup_project
    end

    it "should ensure user has logged in" do
      hooks(@main, :ssh).should include(:logged_in?)
    end

    it "should execute ssh command" do
      @app.should_receive(:ssh_console)
      invoke(@main, :ssh)
    end

    context "virtual servers are not running" do
      it "should display error" do
        @client.stub(:tunnel).and_raise(Shelly::Client::ConflictException)
        $stdout.should_receive(:puts).with(red "Cloud foo-production is not running. Cannot run ssh console.")
        lambda {
          invoke(@main, :ssh)
        }.should raise_error(SystemExit)
      end
    end

    context "virtual server not found" do
      it "should display error" do
        ex = Shelly::Client::NotFoundException.new("resource" => "virtual_server")
        @client.stub(:tunnel).and_raise(ex)
        @main.options = {:server => "foobar"}
        $stdout.should_receive(:puts).with(red "Virtual server 'foobar' not found or not configured for running ssh console")
        lambda {
          invoke(@main, :ssh)
        }.should raise_error(SystemExit)
      end
    end
  end

  describe "#check" do
    before do
      Shelly::App.stub(:inside_git_repository?).and_return(true)
      Bundler::Definition.stub_chain(:build, :specs, :map) \
        .and_return(["thin", "pg", "delayed_job", "whenever", "sidekiq"])
        Bundler::Definition.stub_chain(:build, :ruby_version).
          and_return(mock(:engine => 'ruby', :version => '2.2.0'))
      Shelly::StructureValidator.any_instance.stub(:repo_paths) \
        .and_return(["config.ru", "Gemfile", "Gemfile.lock", "Rakefile"])
      Shelly::StructureValidator.any_instance.stub(:tasks).and_return(["rake db:migrate"])
    end

    it "should ensure user is in git repository" do
      hooks(@main, :check).should include(:inside_git_repository?)
    end

    context "when gemfile exists" do
      it "should show that Gemfile exists" do
        $stdout.should_receive(:puts).with("  #{green("✓")} Gemfile is present")
        invoke(@main, :check)
      end
    end

    context "when gemfile doesn't exist" do
      it "should show that Gemfile doesn't exist" do
        Shelly::StructureValidator.any_instance.stub(:repo_paths).and_return([])
        $stdout.should_receive(:puts).with("  #{red("✗")} Gemfile is missing in git repository")
        invoke(@main, :check)
      end
    end

    context "when gemfile exists" do
      it "should show that Gemfile exists" do
        $stdout.should_receive(:puts).with("  #{green("✓")} Gemfile is present")
        invoke(@main, :check)
      end
    end

    context "when gemfile doesn't exist" do
      it "should show that Gemfile doesn't exist" do
        Shelly::StructureValidator.any_instance.stub(:repo_paths).and_return([])
        $stdout.should_receive(:puts).with("  #{red("✗")} Gemfile is missing in git repository")
        invoke(@main, :check)
      end
    end

    context "application server" do
      context "when thin gem exists" do
        it "should show that necessary gem exists" do
          $stdout.should_receive(:puts).with("  #{green("✓")} Web server gem is present")
          invoke(@main, :check)
        end
      end

      context "when puma gem exists" do
        it "should show that necessary gem exists" do
          Bundler::Definition.stub_chain(:build, :specs, :map) \
            .and_return(["puma", "pg", "delayed_job", "whenever", "sidekiq"])
          $stdout.should_receive(:puts).with("  #{green("✓")} Web server gem is present")
          invoke(@main, :check)
        end
      end

      context "when neither thin nor puma present in Gemfile" do
        it "should show that necessary gem doesn't exist" do
          Bundler::Definition.stub_chain(:build, :specs, :map).and_return([])
          $stdout.should_receive(:puts).with("  #{red("✗")} Missing web server gem in Gemfile. Currently supported: 'thin' and 'puma'")
          invoke(@main, :check)
        end
      end
    end

    context "gemfile ruby version" do
      context "ruby engine" do
        context "supported version" do
          it "should show checked message" do
            Bundler::Definition.stub_chain(:build, :ruby_version).
              and_return(mock(:engine => 'ruby', :version => '2.2.0'))

            $stdout.should_receive(:puts).with("  #{green("✓")} ruby 2.2.0 is supported")
            invoke(@main, :check)
          end
        end

        context "unsupported version" do
          it "should show error message" do
            Bundler::Definition.stub_chain(:build, :ruby_version).
              and_return(mock(:engine => 'ruby', :version => '1.9.2'))

            $stdout.should_receive(:puts).with("  #{red("✗")} ruby 1.9.2 is currently unsupported\n    See more at https://shellycloud.com/documentation/requirements#ruby_versions")
            invoke(@main, :check)
          end
        end
      end

      context "jruby engine" do
        context "supported version" do
          it "should show checked message" do
            Bundler::Definition.stub_chain(:build, :ruby_version).
              and_return(mock(:engine => 'jruby', :version => '1.9.3', :engine_version => '1.7.10'))

            $stdout.should_receive(:puts).with("  #{green("✓")} jruby 1.7.10 (1.9 mode) is supported")
            invoke(@main, :check)
          end
        end

        context "unsupported version" do
          it "should show error message - ruby version" do
            Bundler::Definition.stub_chain(:build, :ruby_version).
              and_return(mock(:engine => 'jruby', :version => '1.8.7', :engine_version => '1.7.10'))

            $stdout.should_receive(:puts).with("  #{red("✗")} Only jruby 1.7.10 (1.9 mode) is currently supported\n    See more at https://shellycloud.com/documentation/requirements#ruby_versions")
            invoke(@main, :check)
          end

          it "should show error message - engine version" do
            Bundler::Definition.stub_chain(:build, :ruby_version).
              and_return(mock(:engine => 'jruby', :version => '1.9.3', :engine_version => '1.7.3'))

            $stdout.should_receive(:puts).with("  #{red("✗")} Only jruby 1.7.10 (1.9 mode) is currently supported\n    See more at https://shellycloud.com/documentation/requirements#ruby_versions")
            invoke(@main, :check)
          end
        end
      end

      context "patchlevel version" do
        it "should show unsupported error message" do
          Bundler::Definition.stub_chain(:build, :ruby_version).
            and_return(mock(:engine => 'ruby', :version => '1.9.3', :patchlevel => '111'))

          $stdout.should_receive(:puts).with("  #{red("✗")} Remove Ruby patchlevel from Gemfile\n    Shelly Cloud takes care of upgrading Rubies whenever they are released\n    See more at https://shellycloud.com/documentation/requirements#ruby_versions")
          invoke(@main, :check)
        end
      end

      context "other engines" do
        it "should show unsupported error message" do
          Bundler::Definition.stub_chain(:build, :ruby_version).
            and_return(mock(:engine => 'mswin', :version => '1.9.2'))

          $stdout.should_receive(:puts).with("  #{red("✗")} Your ruby engine: mswin is currently unsupported\n    See more at https://shellycloud.com/documentation/requirements#ruby_versions")
          invoke(@main, :check)
        end
      end
    end

    context "when 'db:migrate' task exists" do
      it "should show that necessary task exists" do
        $stdout.should_receive(:puts).with("  #{green("✓")} Task 'db:migrate' is present")
        invoke(@main, :check)
      end
    end

    context "when 'db:migrate' task doesn't exist" do
      it "should show that necessary task doesn't exist" do
        Shelly::StructureValidator.any_instance.stub(:tasks).and_return([])
        $stdout.should_receive(:puts).with("  #{red("✗")} Task 'db:migrate' is missing")
        invoke(@main, :check)
      end
    end

    context "when config.ru exists" do
      it "should show that config.ru exists" do
        $stdout.should_receive(:puts).with("  #{green("✓")} config.ru is present")
        invoke(@main, :check)
      end
    end

    context "when config.ru doesn't exist" do
      it "should show that config.ru is neccessary" do
        Shelly::StructureValidator.any_instance.stub(:repo_paths).and_return([])
        $stdout.should_receive(:puts).with("  #{red("✗")} config.ru is missing")
        invoke(@main, :check)
      end
    end

    context "when Rakefile exists" do
      it "should show that Rakefile exists" do
        $stdout.should_receive(:puts).with("  #{green("✓")} Rakefile is present")
        invoke(@main, :check)
      end
    end

    context "when Rakefile doesn't exist" do
      it "should show that Rakefile is neccessary" do
        Shelly::StructureValidator.any_instance.stub(:repo_paths).and_return([])
        $stdout.should_receive(:puts).with("  #{red("✗")} Rakefile is missing")
        invoke(@main, :check)
      end
    end

    context "when Gemfile contains 'shelly' gem" do
      it "should show warning" do
        Bundler::Definition.stub_chain(:build, :specs, :map).
          and_return(["shelly"])
        $stdout.should_receive(:puts).
          with("  #{yellow("ϟ")} Gem 'shelly' should not be a part of Gemfile.\n    The versions of the thor gem used by shelly and Rails may be incompatible.")
        invoke(@main, :check)
      end
    end

    context "when Gemfile does not contains 'shelly' gem" do
      it "should show that 'shelly' is not a part of Gemfile" do
        $stdout.should_receive(:puts).
          with("  #{green("✓")} Gem 'shelly' is not a part of Gemfile")
        invoke(@main, :check)
      end
    end

    context "cloudfile" do
      before do
        cloud = mock(:code_name => "foo-staging", :cloud_databases => ["postgresql"],
          :whenever? => true, :delayed_job? => true, :sidekiq? => true,
          :thin? => true, :puma? => true, :to_s => "foo-staging")
        cloudfile = mock(:clouds => [cloud])

        Shelly::Cloudfile.stub(:new).and_return(cloudfile)
      end

      context "whenever is enabled" do
        it "should show that necessary gem doesn't exist" do
          Bundler::Definition.stub_chain(:build, :specs, :map).and_return([])
          $stdout.should_receive(:puts).with("  #{red("✗")} Gem 'whenever' is missing in the Gemfile for 'foo-staging' cloud")
          invoke(@main, :check)
        end

        it "should show that necessary gem exists" do
          $stdout.should_receive(:puts).with("  #{green("✓")} Gem 'whenever' is present for 'foo-staging' cloud")
          invoke(@main, :check)
        end
      end

      context "delayed_job is enabled" do
        it "should show that necessary gem doesn't exist" do
          Bundler::Definition.stub_chain(:build, :specs, :map).and_return([])
          $stdout.should_receive(:puts).with("  #{red("✗")} Gem 'delayed_job' is missing in the Gemfile for 'foo-staging' cloud")
          invoke(@main, :check)
        end

        it "should show that necessary gem exists" do
          $stdout.should_receive(:puts).with("  #{green("✓")} Gem 'delayed_job' is present for 'foo-staging' cloud")
          invoke(@main, :check)
        end
      end

      context "sidekiq is enabled" do
        it "should show that necessary gem doesn't exist" do
          Bundler::Definition.stub_chain(:build, :specs, :map).and_return([])
          $stdout.should_receive(:puts).with("  #{red("✗")} Gem 'sidekiq' is missing in the Gemfile for 'foo-staging' cloud")
          invoke(@main, :check)
        end

        it "should show that necessary gem exists" do
          $stdout.should_receive(:puts).with("  #{green("✓")} Gem 'sidekiq' is present for 'foo-staging' cloud")
          invoke(@main, :check)
        end
      end

      context "postgresql is enabled" do
        it "should show that necessary gem doesn't exist" do
          Bundler::Definition.stub_chain(:build, :specs, :map).and_return([])
          $stdout.should_receive(:puts).with("  #{red("✗")} Postgresql driver is missing in the Gemfile for 'foo-staging' cloud,\n    we recommend adding 'pg' gem to Gemfile")
          invoke(@main, :check)
        end

        it "should show that necessary gem exists - postgres" do
          Bundler::Definition.stub_chain(:build, :specs, :map).and_return(["postgres"])
          $stdout.should_receive(:puts).with("  #{green("✓")} Postgresql driver is present for 'foo-staging' cloud")
          invoke(@main, :check)
        end

        it "should show that necessary gem exists - pg" do
          Bundler::Definition.stub_chain(:build, :specs, :map).and_return(["pg"])
          $stdout.should_receive(:puts).with("  #{green("✓")} Postgresql driver is present for 'foo-staging' cloud")
          invoke(@main, :check)
        end
      end

      context "thin web server" do
        it "should show that necessary gem doesn't exist" do
          Bundler::Definition.stub_chain(:build, :specs, :map).and_return([])
          $stdout.should_receive(:puts).with("  #{red("✗")} Gem 'thin' is missing in the Gemfile for 'foo-staging' cloud")
          invoke(@main, :check)
        end

        it "should show that necessary gem exists" do
          Bundler::Definition.stub_chain(:build, :specs, :map).and_return(["thin"])
          $stdout.should_receive(:puts).with("  #{green("✓")} Web server gem 'thin' is present for 'foo-staging' cloud")
          invoke(@main, :check)
        end
      end

      context "puma web server" do
        it "should show that necessary gem doesn't exist" do
          Bundler::Definition.stub_chain(:build, :specs, :map).and_return([])
          $stdout.should_receive(:puts).with("  #{red("✗")} Gem 'puma' is missing in the Gemfile for 'foo-staging' cloud")
          invoke(@main, :check)
        end

        it "should show that necessary gem exists" do
          Bundler::Definition.stub_chain(:build, :specs, :map).and_return(["puma"])
          $stdout.should_receive(:puts).with("  #{green("✓")} Web server gem 'puma' is present for 'foo-staging' cloud")
          invoke(@main, :check)
        end
      end
    end

    context "when bundler raise error" do
      it "should display error message" do
        exception = Bundler::BundlerError.new('Bundler error')
        Bundler::Definition.stub(:build).and_raise(exception)
        $stdout.should_receive(:puts).with(red "Bundler error")
        $stdout.should_receive(:puts).with(red "Try to run `bundle install`")
        lambda {
          invoke(@main, :check)
        }.should raise_error(SystemExit)
      end
    end

    it "should display only errors and warnings when in verbose mode" do
      $stdout.should_not_receive(:puts).with("  #{green("✓")} Gem 'thin' is present")
      $stdout.should_not_receive(:puts).with("  #{green("✓")} Task 'db:migrate' is present")
      $stdout.should_receive(:puts).with("  #{yellow("ϟ")} Gem 'shelly-dependencies' is missing, we recommend to install it\n    See more at https://shellycloud.com/documentation/requirements#shelly-dependencies")
      $stdout.should_receive(:puts).with("  #{red("✗")} Gem 'rake' is missing in the Gemfile")
      $stdout.should_receive(:puts).with("  #{red("✗")} Task 'db:setup' is missing")
      $stdout.should_receive(:puts).with("\nFix points marked with #{red("✗")} to run your application on the Shelly Cloud")
      $stdout.should_receive(:puts).with("See more about requirements on https://shellycloud.com/documentation/requirements")
      @main.check(false)
    end
  end

  def setup_project(code_name = "foo")
    @app = Shelly::App.new("#{code_name}-production")
    Shelly::App.stub(:new).and_return(@app)
    FileUtils.mkdir_p("/projects/#{code_name}")
    Dir.chdir("/projects/#{code_name}")
    File.open("Cloudfile", 'w') { |f| f.write("#{code_name}-production:\n") }
  end
end
