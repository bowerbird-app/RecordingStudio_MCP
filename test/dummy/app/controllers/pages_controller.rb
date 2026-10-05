# frozen_string_literal: true

class PagesController < ApplicationController
  def index
    @page_recordings = accessible_page_recordings
  end

  def update
    recording = find_accessible_page
    if recording.nil?
      redirect_to pages_path, alert: "That page isn’t here, or it isn’t yours."
      return
    end
    unless RecordingStudioAccessible.authorized?(actor: current_user, recording: recording, role: :edit)
      redirect_to pages_path, alert: "You can look, but you can’t save this one."
      return
    end

    root = recording.root_recording || recording
    root.revise(recording, actor: current_user) do |page|
      page.title = params[:title].to_s
      page.body = params[:body].to_s if page.respond_to?(:body=)
    end

    redirect_to pages_path, notice: "Saved. Watchers can read it again."
  end

  def comment
    recording = find_accessible_page
    if recording.nil?
      redirect_to pages_path, alert: "That page isn’t here, or it isn’t yours."
      return
    end

    RecordingStudioMcp.notify("page commented", recording: recording)
    redirect_to pages_path, notice: "Pinged the watchers."
  end

  private

  def find_accessible_page
    accessible_page_recordings.find { |recording| recording.id.to_s == params[:id].to_s }
  end

  def accessible_page_recordings
    roots = RecordingStudioAccessible.root_recordings_for(actor: current_user)
    roots.flat_map { |root| pages_under(root) }
         .select { |recording| RecordingStudioAccessible.authorized?(actor: current_user, recording: recording, role: :view) }
         .sort_by { |recording| recording.recordable&.title.to_s }
  end

  def pages_under(root)
    return [] unless root.respond_to?(:recordings_of)

    relation = root.recordings_of("Page")
    relation = relation.includes(:recordable) if relation.respond_to?(:includes)
    Array(relation)
  end
end
