class Projects::BuildsController < Projects::ApplicationController
  before_action :build, except: [:index, :cancel_all]

  before_action :authorize_manage_builds!, except: [:index, :show, :status]
  before_action :authorize_download_build_artifacts!, only: [:download]

  layout "project"

  def index
    @scope = params[:scope]
    @all_builds = project.builds
    @builds = @all_builds.order('created_at DESC')
    @builds =
      case @scope
      when 'running'
        @builds.running_or_pending.reverse_order
      when 'finished'
        @builds.finished
      else
        @builds
      end
    @builds = @builds.page(params[:page]).per(30)
  end

  def cancel_all
    @project.builds.running_or_pending.each(&:cancel)

    redirect_to namespace_project_builds_path(project.namespace, project)
  end

  def show
    @builds = @project.ci_commits.find_by_sha(@build.sha).builds.order('id DESC')
    @builds = @builds.where("id not in (?)", @build.id)
    @commit = @build.commit

    respond_to do |format|
      format.html
      format.json do
        render json: @build.to_json(methods: :trace_html)
      end
    end
  end

  def retry
    unless @build.retryable?
      return page_404
    end

    build = Ci::Build.retry(@build)

    redirect_to build_path(build)
  end

  def download
    unless artifacts_file.file_storage?
      return redirect_to artifacts_file.url
    end

    unless artifacts_file.exists?
      return not_found!
    end

    send_file artifacts_file.path, disposition: 'attachment'
  end

  def status
    render json: @build.to_json(only: [:status, :id, :sha, :coverage], methods: :sha)
  end

  def cancel
    @build.cancel

    redirect_to build_path(@build)
  end

  private

  def build
    @build ||= project.builds.unscoped.find_by!(id: params[:id])
  end

  def artifacts_file
    build.artifacts_file
  end

  def build_path(build)
    namespace_project_build_path(build.project.namespace, build.project, build)
  end

  def authorize_manage_builds!
    unless can?(current_user, :manage_builds, project)
      return page_404
    end
  end

  def authorize_download_build_artifacts!
    unless can?(current_user, :download_build_artifacts, @project)
      if current_user.nil?
        return authenticate_user!
      else
        return render_404
      end
    end
  end
end
