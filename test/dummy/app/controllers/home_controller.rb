class HomeController < ApplicationController
  def index
    @page_recording = demo_page_recording
    @page_title = @page_recording&.recordable&.title
  end

  def save_change
    recording = demo_page_recording
    if recording.nil?
      redirect_to root_path, alert: "Add a page first, then try again."
      return
    end

    root = recording.root_recording || recording
    root.revise(recording, actor: current_user) do |page|
      page.title = next_page_title(page.title)
    end

    redirect_to root_path, notice: "Saved. Watchers can read it again."
  end

  private

  def demo_page_recording
    studio = Workspace.find_by(name: "Studio Workspace")
    if studio
      root = RecordingStudio.root_recording_for(studio)
      found = root.recordings_of("Page").first if root.respond_to?(:recordings_of)
      return found if found
    end

    RecordingStudio::Recording.where(recordable_type: "Page").order(:id).first
  end

  def next_page_title(current)
    stamp = Time.current.strftime("%H:%M:%S")
    base = current.to_s.sub(/\s+\d{2}:\d{2}:\d{2}\z/, "")
    base = "Getting Started" if base.blank?
    "#{base} #{stamp}"
  end
end
