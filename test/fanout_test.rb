# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"
require "active_record"

class FanoutTest < Minitest::Test
  FakeGrant = Struct.new(:allowed_ids) do
    def accessible_recordings
      ids = allowed_ids
      Object.new.tap do |scope|
        scope.define_singleton_method(:exists?) { |id:| ids.include?(id) }
        scope.define_singleton_method(:find_by) { |id:| ids.include?(id) ? Object.new : nil }
      end
    end
  end

  FakeRecording = Struct.new(:id, :recordable_type)

  def test_non_postgres_delivers_in_process
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([4])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://4")

      RecordingStudioMcp::Notifier.stub(:find_recording, FakeRecording.new(4, "Page")) do
        RecordingStudioMcp::PostgresBus.stub(:enabled?, false) do
          RecordingStudioMcp::Fanout.publish(
            event_name: "recording updated",
            recording_id: 4,
            recording: FakeRecording.new(4, "Page")
          )
        end
      end

      assert_equal "recording://4", connection.shift_pending(timeout: 0).dig(:params, :uri)
    end
  end

  def test_postgres_listening_path_notifies_without_local_enqueue
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      published = []
      local = []
      RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
        RecordingStudioMcp::PostgresBus.stub(:listening?, true) do
          RecordingStudioMcp::PostgresBus.stub(:publish_payload, lambda { |payload|
            published << payload
          }) do
            RecordingStudioMcp::Notifier.stub(:deliver_local, lambda { |**kwargs|
              local << kwargs
            }) do
              RecordingStudioMcp::Fanout.publish(event_name: "recording updated", recording_id: 11)
            end
          end
        end
      end

      assert_equal 1, published.size
      assert_includes published.first, '"event":"recording updated"'
      assert_includes published.first, '"id":"11"'
      assert_empty local
    end
  end

  def test_postgres_non_listening_publisher_notifies_and_delivers_local
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      published = []
      local = []
      RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
        RecordingStudioMcp::PostgresBus.stub(:listening?, false) do
          RecordingStudioMcp::PostgresBus.stub(:publish_payload, lambda { |payload|
            published << payload
          }) do
            RecordingStudioMcp::Notifier.stub(:deliver_local, lambda { |**kwargs|
              local << [kwargs[:event_name], kwargs[:recording_id]]
            }) do
              RecordingStudioMcp::Fanout.publish(event_name: "recording updated", recording_id: 12)
            end
          end
        end
      end

      assert_equal 1, published.size
      assert_includes published.first, "recording updated"
      assert_equal [["recording updated", 12]], local
    end
  end

  def test_notify_failure_falls_back_to_local_delivery
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      local = []
      io = StringIO.new
      logger = Logger.new(io)

      RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
        RecordingStudioMcp::PostgresBus.stub(:listening?, true) do
          RecordingStudioMcp::PostgresBus.stub(:publish_payload, lambda { |_|
            raise ActiveRecord::ConnectionNotEstablished, "database down"
          }) do
            RecordingStudioMcp::Notifier.stub(:deliver_local, lambda { |**kwargs|
              local << [kwargs[:event_name], kwargs[:recording_id]]
            }) do
              Rails.stub(:logger, logger) do
                RecordingStudioMcp::Fanout.publish(event_name: "recording updated", recording_id: 13)
              end
            end
          end
        end
      end

      assert_equal [["recording updated", 13]], local
      assert_includes io.string, "NOTIFY failed"
      assert_includes io.string, "ConnectionNotEstablished"
      assert_includes io.string, "delivering locally"
    end
  end

  def test_oversize_notify_payload_falls_back_to_local_delivery
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      published = []
      local = []
      io = StringIO.new
      logger = Logger.new(io)
      huge_id = "x" * RecordingStudioMcp::Fanout::NOTIFY_PAYLOAD_MAX_BYTES

      RecordingStudioMcp::PostgresBus.stub(:enabled?, true) do
        RecordingStudioMcp::PostgresBus.stub(:listening?, true) do
          RecordingStudioMcp::PostgresBus.stub(:publish_payload, lambda { |payload|
            published << payload
          }) do
            RecordingStudioMcp::Notifier.stub(:deliver_local, lambda { |**kwargs|
              local << [kwargs[:event_name], kwargs[:recording_id]]
            }) do
              Rails.stub(:logger, logger) do
                RecordingStudioMcp::Fanout.publish(
                  event_name: "recording updated",
                  recording_id: huge_id
                )
              end
            end
          end
        end
      end

      assert_empty published
      assert_equal [["recording updated", huge_id]], local
      assert_includes io.string, "exceeds #{RecordingStudioMcp::Fanout::NOTIFY_PAYLOAD_MAX_BYTES}"
      assert_includes io.string, "delivering locally"
    end
  end

  def test_bad_listen_payload_is_ignored
    RecordingStudioMcp::PostgresBus.handle_payload("not-json")
    RecordingStudioMcp::PostgresBus.handle_payload({ "event" => "", "id" => "" }.to_json)
  end

  def test_start_is_a_noop_when_postgres_is_disabled
    RecordingStudioMcp::PostgresBus.stub(:enabled?, false) do
      RecordingStudioMcp::PostgresBus.start!
      refute RecordingStudioMcp::PostgresBus.listening?
    end
  end

  def test_listen_payload_rechecks_access_and_local_subscribers
    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      grant = FakeGrant.new([5])
      connection = RecordingStudioMcp::Connections.open(protocol_version: "2025-06-18", access_grant: grant)
      connection.subscribe("recording://5")

      RecordingStudioMcp::Notifier.stub(:find_recording, FakeRecording.new(5, "Page")) do
        RecordingStudioMcp::PostgresBus.handle_payload({ "event" => "recording updated", "id" => "5" }.to_json)
      end

      assert_equal "recording://5", connection.shift_pending(timeout: 0).dig(:params, :uri)
    end
  end

  # Real Postgres: Fanout defers NOTIFY until commit, so a rejected NOTIFY cannot
  # abort later host SQL. Delivery falls back locally exactly once after commit.
  # Belt-and-braces: also force an in-transaction NOTIFY failure through the
  # savepoint path and confirm the outer transaction still commits.
  def test_failing_notify_inside_host_transaction_still_commits_and_delivers_once
    ensure_active_record_connection!
    create_fanout_probe_table!

    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      local = []
      failing_notify = lambda { |_|
        ActiveRecord::Base.connection.execute("SELECT 1/0")
      }

      RecordingStudioMcp::PostgresBus.stub(:listening?, false) do
        RecordingStudioMcp::PostgresBus.stub(:publish_payload, failing_notify) do
          RecordingStudioMcp::Notifier.stub(:deliver_local, lambda { |**kwargs|
            local << [kwargs[:event_name], kwargs[:recording_id]]
          }) do
            ActiveRecord::Base.transaction do
              insert_fanout_probe("before")
              RecordingStudioMcp::Fanout.publish(
                event_name: "recording updated",
                recording_id: 91
              )
              assert_empty local, "local deliver must wait for commit"
              insert_fanout_probe("after")
            end
          end
        end
      end

      assert_equal %w[after before], fanout_probe_labels.sort
      assert_equal [["recording updated", 91]], local

      # Savepoint path: delivery runs inside the open transaction and NOTIFY
      # fails on the caller connection; later statements must still commit.
      create_fanout_probe_table!
      local.clear
      RecordingStudioMcp::AfterCommit.stub(:run, ->(&block) { block.call }) do
        RecordingStudioMcp::PostgresBus.stub(:listening?, false) do
          RecordingStudioMcp::PostgresBus.stub(:publish_payload, failing_notify) do
            RecordingStudioMcp::Notifier.stub(:deliver_local, lambda { |**kwargs|
              local << [kwargs[:event_name], kwargs[:recording_id]]
            }) do
              ActiveRecord::Base.transaction do
                insert_fanout_probe("savepoint-before")
                RecordingStudioMcp::Fanout.publish(
                  event_name: "recording updated",
                  recording_id: 93
                )
                insert_fanout_probe("savepoint-after")
              end
            end
          end
        end
      end

      assert_equal %w[savepoint-after savepoint-before], fanout_probe_labels.sort
      assert_equal [["recording updated", 93]], local
    end
  end

  def test_rolled_back_transaction_delivers_nothing
    ensure_active_record_connection!
    create_fanout_probe_table!

    with_isolated_mcp_configuration do
      RecordingStudioMcp.register_event("recording updated")
      local = []
      notify_attempts = []

      RecordingStudioMcp::PostgresBus.stub(:listening?, false) do
        RecordingStudioMcp::PostgresBus.stub(:publish_payload, lambda { |payload|
          notify_attempts << payload
        }) do
          RecordingStudioMcp::Notifier.stub(:deliver_local, lambda { |**kwargs|
            local << [kwargs[:event_name], kwargs[:recording_id]]
          }) do
            ActiveRecord::Base.transaction do
              insert_fanout_probe("rolled-back")
              RecordingStudioMcp::Fanout.publish(
                event_name: "recording updated",
                recording_id: 92
              )
              assert_empty local, "local deliver must wait for commit"
              assert_empty notify_attempts, "NOTIFY must wait for commit"
              raise ActiveRecord::Rollback
            end
          end
        end
      end

      assert_empty fanout_probe_labels
      assert_empty local
      assert_empty notify_attempts
    end
  end

  private

  def ensure_active_record_connection!
    return if ActiveRecord::Base.connected? && postgres_adapter?

    url = ENV["DATABASE_URL"].to_s.strip
    skip "DATABASE_URL is not set" if url.empty?

    ActiveRecord::Base.establish_connection(url)
    ActiveRecord::Base.connection.verify!
    skip "DATABASE_URL is not Postgres" unless postgres_adapter?
  end

  def postgres_adapter?
    ActiveRecord::Base.connection_db_config.adapter.to_s.match?(/postg/i)
  end

  def create_fanout_probe_table!
    conn = ActiveRecord::Base.connection
    conn.execute("DROP TABLE IF EXISTS fanout_txn_probe")
    conn.execute("CREATE TABLE fanout_txn_probe (label text NOT NULL)")
  end

  def insert_fanout_probe(label)
    quoted = ActiveRecord::Base.connection.quote(label)
    ActiveRecord::Base.connection.execute(
      "INSERT INTO fanout_txn_probe (label) VALUES (#{quoted})"
    )
  end

  def fanout_probe_labels
    ActiveRecord::Base.connection.select_values(
      "SELECT label FROM fanout_txn_probe ORDER BY label"
    )
  end
end
