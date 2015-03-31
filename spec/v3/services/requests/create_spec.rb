require 'spec_helper'

describe Travis::API::V3::Services::Requests::Create do
  let(:repo) { Travis::API::V3::Models::Repository.where(owner_name: 'svenfuchs', name: 'minimal').first }
  let(:sidekiq_requests) { [] }
  before { repo.requests.each(&:delete) }

  let(:sidekiq_payload) do
    expect(sidekiq_requests).not_to be_empty, 'expected at least one sidekiq request to be sent, none sent'
    JSON.load(sidekiq_requests.last['args'].last[:payload]).deep_symbolize_keys
  end

  before { Travis::API::V3::Sidekiq.client = sidekiq_requests }
  after  { Travis::API::V3::Sidekiq.client = nil              }

  describe "not authenticated" do
    before  { post("/v3/repo/#{repo.id}/requests")      }
    example { expect(last_response.status).to be == 403 }
    example { expect(JSON.load(body)).to      be ==     {
      "@type"         => "error",
      "error_type"    => "login_required",
      "error_message" => "login required"
    }}
  end

  describe "missing repository, authenticated" do
    let(:token)   { Travis::Api::App::AccessToken.create(user: repo.owner, app_id: 1) }
    let(:headers) {{ 'HTTP_AUTHORIZATION' => "token #{token}"                        }}
    before        { post("/v3/repo/9999999999/requests", {}, headers)                 }

    example { expect(last_response.status).to be == 404 }
    example { expect(JSON.load(body)).to      be ==     {
      "@type"         => "error",
      "error_type"    => "not_found",
      "error_message" => "repository not found (or insufficient access)",
      "resource_type" => "repository"
    }}
  end

  describe "existing repository, no push access" do
    let(:token)   { Travis::Api::App::AccessToken.create(user: repo.owner, app_id: 1) }
    let(:headers) {{ 'HTTP_AUTHORIZATION' => "token #{token}"                        }}
    before        { post("/v3/repo/#{repo.id}/requests", {}, headers)                 }

    example { expect(last_response.status).to be == 403 }
    example { expect(JSON.load(body)).to      be ==     {
      "@type"         => "error",
      "error_type"    => "push_access_required",
      "error_message" => "push access required",
      "repository"    => {
        "@type"       => "repository",
        "@href"       => "/repo/#{repo.id}",
        "id"          => repo.id,
        "slug"        => "svenfuchs/minimal"}
    }}
  end

  describe "private repository, no access" do
    let(:token)   { Travis::Api::App::AccessToken.create(user: repo.owner, app_id: 1) }
    let(:headers) {{ 'HTTP_AUTHORIZATION' => "token #{token}"                        }}
    before        { repo.update_attribute(:private, true)                             }
    before        { post("/v3/repo/#{repo.id}/requests", {}, headers)                 }
    after         { repo.update_attribute(:private, false)                            }

    example { expect(last_response.status).to be == 404 }
    example { expect(JSON.load(body)).to      be ==     {
      "@type"         => "error",
      "error_type"    => "not_found",
      "error_message" => "repository not found (or insufficient access)",
      "resource_type" => "repository"
    }}
  end

  describe "existing repository, push access" do
    let(:params)  {{}}
    let(:token)   { Travis::Api::App::AccessToken.create(user: repo.owner, app_id: 1)                          }
    let(:headers) {{ 'HTTP_AUTHORIZATION' => "token #{token}"                                                 }}
    before        { Travis::API::V3::Models::Permission.create(repository: repo, user: repo.owner, push: true) }
    before        { post("/v3/repo/#{repo.id}/requests", params, headers)                                      }

    example { expect(last_response.status).to be == 202 }
    example { expect(JSON.load(body)).to      be ==     {
      "@type"              => "pending",
      "remaining_requests" => 10,
      "repository"         => {"@type"=>"repository", "@href"=>"/repo/#{repo.id}", "id"=>repo.id, "slug"=>"svenfuchs/minimal"},
      "request"            => {
        "repository"       =>  {"id"=>repo.id, "owner_name"=>"svenfuchs", "name"=>"minimal"},
        "user"             =>  {"id"=>repo.owner.id},
        "message"          => nil,
        "branch"           => "master",
        "config"           => {}},
      "resource_type"      => "request"
    }}

    example { expect(sidekiq_payload).to be == {
      repository: { id: repo.id, owner_name: 'svenfuchs', name: 'minimal' },
      user:       { id: repo.owner.id },
      message:    nil,
      branch:     'master',
      config:     {}
    }}

    example { expect(sidekiq_requests.last['queue']).to be == 'build_requests'                }
    example { expect(sidekiq_requests.last['class']).to be == 'Travis::Sidekiq::BuildRequest' }

    describe "setting id has no effect" do
      let(:params) {{ id: 42 }}
      example { expect(sidekiq_payload).to be == {
        repository: { id: repo.id, owner_name: 'svenfuchs', name: 'minimal' },
        user:       { id: repo.owner.id },
        message:    nil,
        branch:     'master',
        config:     {}
      }}
    end

    describe "setting repository has no effect" do
      let(:params) {{ repository: { id: 42 } }}
      example { expect(sidekiq_payload).to be == {
        repository: { id: repo.id, owner_name: 'svenfuchs', name: 'minimal' },
        user:       { id: repo.owner.id },
        message:    nil,
        branch:     'master',
        config:     {}
      }}
    end

    describe "setting user has no effect" do
      let(:params) {{ user: { id: 42 } }}
      example { expect(sidekiq_payload).to be == {
        repository: { id: repo.id, owner_name: 'svenfuchs', name: 'minimal' },
        user:       { id: repo.owner.id },
        message:    nil,
        branch:     'master',
        config:     {}
      }}
    end

    describe "overriding config" do
      let(:params) {{ config: { script: 'true' } }}
      example { expect(sidekiq_payload).to be == {
        repository: { id: repo.id, owner_name: 'svenfuchs', name: 'minimal' },
        user:       { id: repo.owner.id },
        message:    nil,
        branch:     'master',
        config:     { script: 'true' }
      }}
    end

    describe "overriding message" do
      let(:params) {{ message: 'example' }}
      example { expect(sidekiq_payload).to be == {
        repository: { id: repo.id, owner_name: 'svenfuchs', name: 'minimal' },
        user:       { id: repo.owner.id },
        message:    'example',
        branch:     'master',
        config:     {}
      }}
    end

    describe "overriding branch" do
      let(:params) {{ branch: 'example' }}
      example { expect(sidekiq_payload).to be == {
        repository: { id: repo.id, owner_name: 'svenfuchs', name: 'minimal' },
        user:       { id: repo.owner.id },
        message:    nil,
        branch:     'example',
        config:     {}
      }}
    end

    describe "overriding branch (in request)" do
      let(:params) {{ request: { branch: 'example' } }}
      example { expect(sidekiq_payload).to be == {
        repository: { id: repo.id, owner_name: 'svenfuchs', name: 'minimal' },
        user:       { id: repo.owner.id },
        message:    nil,
        branch:     'example',
        config:     {}
      }}
    end

    describe "overriding branch (with request prefix)" do
      let(:params) {{ "request.branch" => 'example' }}
      example { expect(sidekiq_payload).to be == {
        repository: { id: repo.id, owner_name: 'svenfuchs', name: 'minimal' },
        user:       { id: repo.owner.id },
        message:    nil,
        branch:     'example',
        config:     {}
      }}
    end

    describe "overriding branch (with request type)" do
      let(:params) {{ "@type" => "request", "branch" => 'example' }}
      example { expect(sidekiq_payload).to be == {
        repository: { id: repo.id, owner_name: 'svenfuchs', name: 'minimal' },
        user:       { id: repo.owner.id },
        message:    nil,
        branch:     'example',
        config:     {}
      }}
    end

    describe "overriding branch (with wrong type)" do
      let(:params) {{ "@type" => "repository", "branch" => 'example' }}
      example { expect(sidekiq_payload).to be == {
        repository: { id: repo.id, owner_name: 'svenfuchs', name: 'minimal' },
        user:       { id: repo.owner.id },
        message:    nil,
        branch:     'master',
        config:     {}
      }}
    end

    describe "when request limit is reached" do
      before { 10.times { repo.requests.create(event_type: 'api', result: 'accepted') } }
      before { post("/v3/repo/#{repo.id}/requests", params, headers)                    }

      example { expect(last_response.status).to be == 429 }
      example { expect(JSON.load(body)).to      be ==     {
        "@type"         => "error",
        "error_type"    => "request_limit_reached",
        "error_message" => "request limit reached for resource",
        "repository"    => {"@type"=>"repository", "@href"=>"/repo/#{repo.id}", "id"=>repo.id, "slug"=>"svenfuchs/minimal" }
      }}
    end
  end


  describe "existing repository, application with full access" do
    let(:app_name)   { 'travis-example'                                                           }
    let(:app_secret) { '12345678'                                                                 }
    let(:sign_opts)  { "a=#{app_name}"                                                            }
    let(:signature)  { OpenSSL::HMAC.hexdigest('sha256', app_secret, sign_opts)                   }
    let(:headers)    {{ 'HTTP_AUTHORIZATION' => "signature #{sign_opts}:#{signature}"            }}
    before { Travis.config.applications = { app_name => { full_access: true, secret: app_secret }}}
    before { post("/v3/repo/#{repo.id}/requests", params, headers)                                }

    describe 'without setting user' do
      let(:params) {{}}
      example { expect(last_response.status).to be == 400 }
      example { expect(JSON.load(body)).to      be ==     {
        "@type"         => "error",
        "error_type"    => "wrong_params",
        "error_message" => "missing user"
      }}
    end

    describe 'setting user' do
      let(:params) {{ user: { id: repo.owner.id } }}
      example { expect(last_response.status).to be == 202 }
      example { expect(sidekiq_payload).to be == {
        repository: { id: repo.id, owner_name: 'svenfuchs', name: 'minimal' },
        user:       { id: repo.owner.id },
        message:    nil,
        branch:     'master',
        config:     {}
      }}
    end

    describe 'setting branch' do
      let(:params) {{ user: { id: repo.owner.id }, branch: 'example' }}
      example { expect(last_response.status).to be == 202 }
      example { expect(sidekiq_payload).to be == {
        repository: { id: repo.id, owner_name: 'svenfuchs', name: 'minimal' },
        user:       { id: repo.owner.id },
        message:    nil,
        branch:     'example',
        config:     {}
      }}
    end
  end
end