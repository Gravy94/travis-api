module Travis::API::V3
  module Routes
    require 'travis/api/v3/routes/dsl'
    extend DSL

    resource :repository do
      route '/repo/{repository.id}'
      get :find

      post :enable,  '/enable'
      post :disable, '/disable'

      resource :requests do
        route '/requests'
        get  :find
        post :create
      end

      resource :branch do
        route '/branch/{branch.name}'
        get :find
      end
    end

    resource :repositories do
      route '/repos'
      get :for_current_user
    end

    resource :build do
      route '/build/{build.id}'
      get :find
    end

    resource :user do
      route '/user'
      get  :current
      get  :find, '/{user.id}'
      post :sync, '/{user.id}/sync'
    end

    resource :organization do
      route '/org/{organization.id}'
      get :find
    end

    resource :organizations do
      route '/orgs'
      get :for_current_user
    end
  end
end
