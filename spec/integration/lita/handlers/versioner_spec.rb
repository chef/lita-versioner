require "spec_helper"
require "tmpdir"
require "fileutils"

describe Lita::Handlers::Versioner, lita_handler: true, additional_lita_handlers: Lita::Handlers::BumpbotHandler do
  include LitaHelpers

  # Initialize lita
  before do
    Lita.config.handlers.versioner.projects = {
      "lita-test" => {
        pipeline: "lita-test-trigger-release",
        github_url: git_remote,
        version_bump_command: "cat a.txt >> file.txt",
        version_show_command: "cat file.txt",
        dependency_update_command: "cat a.txt > deps.txt",
        inform_channel: "notifications",
      },
    }
  end

  let(:git_remote) { File.join(tmpdir, "lita-test") }

  # Create a repository with file.txt = A, deps.txt=X
  attr_reader :initial_commit_sha
  before do
    create_remote_git_repo(git_remote, "a.txt" => "A", "file.txt" => "A", "deps.txt" => "X")
    @initial_commit_sha = git_sha(git_remote)
  end

  # We override route() - therefore, the matcher doesn't work correctly.
  #it { is_expected.to route_command("build lita-test").to(:build) }
  it { is_expected.to route_http(:post, "/github_handler").to(:github_handler) }

  with_jenkins_server "http://manhattan.ci.chef.co"

  context "build" do

    it "build with no arguments emits a reasonable error message" do
      send_command("build")

      expect(strip_log_data(reply_string)).to eq(strip_eom_block(<<-EOM))
        No project specified!
        Usage: build PROJECT [GIT_REF]   - Kicks off a build for PROJECT with GIT_REF. GIT_REF default: master.
        Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
      EOM
    end

    it "build blarghle emits a reasonable error message" do
      send_command("build blarghle")
      expect(strip_log_data(reply_string)).to eq(strip_eom_block(<<-EOM))
        Invalid project blarghle. Valid projects: lita-test.
        Usage: build PROJECT [GIT_REF]   - Kicks off a build for PROJECT with GIT_REF. GIT_REF default: master.
        Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
      EOM
    end

    it "build lita-test master blarghle does not build (too many arguments)" do
      send_command("build lita-test master blarghle")

      expect(strip_log_data(reply_string)).to eq(strip_eom_block(<<-EOM))
        Too many arguments (3 for 2)!
        Usage: build PROJECT [GIT_REF]   - Kicks off a build for PROJECT with GIT_REF. GIT_REF default: master.
        Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
      EOM
    end

    it "build lita-test builds a release build of master" do
      expect_jenkins_build("/job/lita-test-trigger-release", git_ref: "master", initiated_by: "Test User")

      send_command("build lita-test")

      expect(strip_log_data(reply_string)).to eq(strip_eom_block(<<-EOM))
        Kicked off a build for 'lita-test-trigger-release' at ref 'master'.
      EOM
    end

    it "build lita-test example builds an ad-hoc build with the specified tag" do
      expect_jenkins_build("/job/lita-test-trigger-ad_hoc", git_ref: "example", initiated_by: "Test User")

      send_command("build lita-test example")

      expect(strip_log_data(reply_string)).to eq(strip_eom_block(<<-EOM))
        Kicked off a build for 'lita-test-trigger-ad_hoc' at ref 'example'.
      EOM
    end
  end

  context "bump" do
    it "build with no arguments emits a reasonable error message" do
      send_command("bump")

      expect(strip_log_data(reply_string)).to eq(strip_eom_block(<<-EOM))
        No project specified!
        Usage: bump PROJECT   - Bumps the version of PROJECT and starts a build.
        Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
      EOM
    end

    it "build blarghle emits a reasonable error message" do
      send_command("bump blarghle")

      expect(strip_log_data(reply_string)).to eq(strip_eom_block(<<-EOM))
        Invalid project blarghle. Valid projects: lita-test.
        Usage: bump PROJECT   - Bumps the version of PROJECT and starts a build.
        Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
      EOM
    end

    it "bump lita-test blarghle does not bump (too many arguments)" do
      send_command("bump lita-test blarghle")

      expect(strip_log_data(reply_string)).to eq(strip_eom_block(<<-EOM))
        Too many arguments (2 for 1)!
        Usage: bump PROJECT   - Bumps the version of PROJECT and starts a build.
        Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
      EOM
    end

    it "bump lita-test bumps the version of lita-test" do
      expect_jenkins_build("/job/lita-test-trigger-release", git_ref: "vAA", initiated_by: "Test User")

      send_command("bump lita-test")

      expect(strip_log_data(reply_string)).to eq(strip_eom_block(<<-EOM))
        Bumped version of lita-test to </TMPDIR/lita-test/tree/vAA|vAA> and kicked off a release build.
      EOM

      expect(git_file(git_remote, "file.txt")).to eq("AA")
    end

    # TODO avoid this situation!!
    # Disabled this test because it fails intermittently (it's a race test)
    # it "two bump lita-tests at once triggers two builds but only one actual bump" do
    #   expect(jenkins_http).to receive(:post).with(
    #     "/job/lita-test-trigger-release/buildWithParameters",
    #     {"GIT_REF"=>"vAA", "EXPIRE_CACHE"=>false, "INITIATED_BY"=>"Test User"}).twice
    #
    #   t = Thread.new do
    #     send_command("bump lita-test")
    #   end
    #   send_command("bump lita-test")
    #   t.join
    #
    #   expect(strip_log_data(reply_string)).to eq(strip_eom_block(<<-EOM))
    #     Bumped version to AA
    #     Bumped version of lita-test to </TMPDIR/lita-test/tree/vAA|vAA> and kicked off a release build.
    #     Bumped version to AA
    #     Bumped version of lita-test to </TMPDIR/lita-test/tree/vAA|vAA> and kicked off a release build.
    #   EOM
    #
    #   expect(git_file(git_remote, "file.txt")).to eq("AA")
    # end

    # it "when a commit comes in after the bump command is received, the bump command fails to push" do
    #   expect(jenkins_http).to receive(:post).with(
    #     "/job/lita-test-trigger-release/buildWithParameters",
    #     {"GIT_REF"=>"vAA", "EXPIRE_CACHE"=>false, "INITIATED_BY"=>"Test User"})
    #   send_command("bump lita-test")
    #   create_commit(git_remote, "file.txt")
    # end

    it "bump lita-test followed by bump lita-test bumps the version from subsequent SHAs" do
      expect_jenkins_build("/job/lita-test-trigger-release", git_ref: "vAA", initiated_by: "Test User")

      send_command("bump lita-test")

      expect(git_file(git_remote, "file.txt")).to eq("AA")

      expect_jenkins_build("/job/lita-test-trigger-release", git_ref: "vAAA", initiated_by: "Test User")

      send_command("bump lita-test")

      expect(strip_log_data(reply_string)).to eq(strip_eom_block(<<-EOM))
        Bumped version of lita-test to </TMPDIR/lita-test/tree/vAA|vAA> and kicked off a release build.
        Bumped version of lita-test to </TMPDIR/lita-test/tree/vAAA|vAAA> and kicked off a release build.
      EOM

      expect(git_file(git_remote, "file.txt")).to eq("AAA")
    end
  end

  context "github handler" do
    def post_github_event(event_type, repository, pull_request_action, pull_request_merged, sha: initial_commit_sha, pull_number: 1)
      http.post "/github_handler" do |req|
        req.headers["X-GitHub-Event"] = event_type
        req.params[:payload] = {
          repository: {
            name: repository,
          },
          action: pull_request_action,
          pull_request: {
            merged: pull_request_merged,
            url: "https://api.github.com/repos/chef/#{repository}/pulls/#{pull_number}",
            html_url: "https://github.com/chef/#{repository}/pulls/#{pull_number}",
            merge_commit_sha: sha,
          },
        }.to_json
      end
    end

    context "for events other than pull-request" do
      it "skips build" do
        response = post_github_event("issues", "lita-test", "closed", false)
        expect(response.status).to eq(200)

        expect(git_file(git_remote, "file.txt")).to eq("A")

        expect(replies).to be_empty
        expect(strip_log_data(response.body)).to eq(reply_string)
      end
    end

    context "for unsupported projects" do
      it "skips build" do
        response = post_github_event("pull_request", "blarghle", "closed", true)
        expect(response.status).to eq(500)
        expect(git_file(git_remote, "file.txt")).to eq("A")

        expect(strip_log_data(reply_string)).to eq(strip_eom_block(<<-EOM))
          Repository 'blarghle' is not monitored by versioner!
          Failed. <http://localhost:8080/bumpbot/handlers/1/handler.log|Full log available here.>
        EOM
      end
    end

    context "for non-closed merges" do
      it "skips build" do
        response = post_github_event("pull_request", "lita-test", "opened", true)
        expect(response.status).to eq(200)
        expect(git_file(git_remote, "file.txt")).to eq("A")

        expect(response.body.strip).to eq("")
        expect(replies).to be_empty
      end
    end

    context "for pull-request events without merge" do
      it "skips build" do
        response = post_github_event("pull_request", "lita-test", "closed", false)
        expect(response.status).to eq(200)
        expect(git_file(git_remote, "file.txt")).to eq("A")

        expect(strip_log_data(reply_string)).to eq(strip_eom_block(<<-EOM))
        EOM
        expect(strip_log_data(response.body)).to eq(reply_string)
      end
    end

    context "for merged pull-requests" do
      it "bumps version and runs the build" do
        sha = create_commit(git_remote, "file.txt" => "Z")

        expect_jenkins_build("/job/lita-test-trigger-release", git_ref: "vZA", initiated_by: "BumpBot")

        response = post_github_event("pull_request", "lita-test", "closed", true, sha: sha)
        expect(response.status).to eq(200)

        expect(git_file(git_remote, "file.txt")).to eq("ZA")

        expect(strip_log_data(reply_string)).to eq(strip_eom_block(<<-EOM))
          Bumped version of lita-test to </TMPDIR/lita-test/tree/vZA|vZA> and kicked off a release build.
        EOM
        expect(strip_log_data(response.body)).to eq(strip_eom_block(<<-EOM))
          Bumped version of lita-test to </TMPDIR/lita-test/tree/vZA|vZA> and kicked off a release build.
        EOM
      end

      it "when another commit has been created before the merge is triggered, it fails to push but then handles the next merge" do
        sha1 = create_commit(git_remote, "file.txt" => "Z")
        sha2 = create_commit(git_remote, "file.txt" => "ZZ")

        response = post_github_event("pull_request", "lita-test", "closed", true, sha: sha1)
        expect(response.status).to eq(200)
        expect(response.body.strip).to eq("")

        expect(git_file(git_remote, "file.txt")).to eq("ZZ")

        expect_jenkins_build("/job/lita-test-trigger-release", git_ref: "vZZA", initiated_by: "BumpBot")

        response2 = post_github_event("pull_request", "lita-test", "closed", true, sha: sha2, pull_number: 2)
        expect(response2.status).to eq(200)

        expect(git_file(git_remote, "file.txt")).to eq("ZZA")
        expect(strip_log_data(response2.body)).to eq(strip_eom_block(<<-EOM))
          Bumped version of lita-test to </TMPDIR/lita-test/tree/vZZA|vZZA> and kicked off a release build.
        EOM

        expect(strip_log_data(reply_string)).to eq(strip_eom_block(<<-EOM))
          Bumped version of lita-test to </TMPDIR/lita-test/tree/vZZA|vZZA> and kicked off a release build.
        EOM
      end
    end
  end
end
