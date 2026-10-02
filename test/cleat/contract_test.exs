defmodule Cleat.ContractTest do
  @moduledoc """
  Guards the CLI against panel API drift.

  `test/fixtures/api_contract.json` is a vendored copy of the panel's
  `priv/api_contract.json` (source: `CleatDeployWeb.Api.Contract`). If the panel
  drops or renames a key the CLI reads, this test fails once the fixture is
  refreshed.
  """

  use ExUnit.Case, async: true

  @fixture "test/fixtures/api_contract.json"

  # Keys the CLI reads from each resource type.
  @used %{
    "app" =>
      ~w(id name slug github_repo branch host port runtime runtime_apt_packages auto_deploy indexable systemd_unit release_path data_dir server),
    "server" =>
      ~w(id name host_ip ssh_user region provider deploy_mode instance_status bundle_name cpu_count ram_mb disk_gb),
    "deployment" =>
      ~w(id app_id git_sha git_ref status triggered_by started_at finished_at inserted_at updated_at wait_reason),
    "deployment_log" =>
      ~w(id app_id git_sha git_ref status triggered_by started_at finished_at inserted_at updated_at wait_reason log),
    "env_var" => ~w(key value branch sensitive revealed),
    "log_event" =>
      ~w(id app_id server_id deployment_id unit source severity message environment fingerprint occurred_at),
    "log_group" => ~w(fingerprint severity count sample last_seen_at),
    "signal_health" =>
      ~w(app_id slug name status reasons error_count previous_error_count preceding_release),
    "signal_metrics" => ~w(app_id slug range red host series deploy_markers),
    "signal_alert" =>
      ~w(id app_id slug rule status message channel fired_at acked_at delivered_at),
    "signal_incident" => ~w(app_id slug events),
    "signal_trace" => ~w(trace_id root_name services started_at duration_ms span_count error),
    "signal_span" =>
      ~w(trace_id span_id parent_span_id name kind service_name status_code start_time_unix_nano duration_ms depth attributes),
    "signal_service_map" => ~w(nodes edges),
    "signal_sampling" => ~w(app_id slug trace_sample_rate),
    "signal_trace_detail" => ~w(trace spans service_map logs),
    "user" => ~w(id email),
    "tenant" => ~w(id name slug),
    "me" => ~w(user tenant role),
    "token" => ~w(token token_id user tenant)
  }

  setup_all do
    {:ok, contract: @fixture |> File.read!() |> Jason.decode!()}
  end

  test "every key the CLI reads is part of the contract", %{contract: contract} do
    Enum.each(@used, fn {resource, used_keys} ->
      contracted = Map.fetch!(contract, resource)

      missing = used_keys -- contracted

      assert missing == [],
             "CLI reads #{inspect(missing)} from #{resource}, not present in the panel contract"
    end)
  end

  test "the CLI knows about every contracted resource", %{contract: contract} do
    unknown = Map.keys(contract) -- Map.keys(@used)

    assert unknown == [],
           "new panel resources are not covered by the CLI contract test: #{inspect(unknown)}"
  end

  test "vendored fixture matches the canonical panel contract" do
    case panel_contract_path() do
      nil ->
        if System.get_env("CI") in ["true", "1"] do
          flunk("""
          CI must compare the fixture against cleat-deploy priv/api_contract.json.
          Set CLEAT_DEPLOY_CONTRACT to that file.
          """)
        else
          :ok
        end

      path ->
        panel = path |> File.read!() |> Jason.decode!()
        fixture = @fixture |> File.read!() |> Jason.decode!()

        assert fixture == panel, """
        CLI fixture drifted from the panel contract at #{path}.
        Copy priv/api_contract.json from cleat-cloud/cleat-deploy into
        test/fixtures/api_contract.json and update @used in this test.
        """
    end
  end

  defp panel_contract_path do
    env = System.get_env("CLEAT_DEPLOY_CONTRACT")
    sibling = Path.expand("../../../cleat-web/priv/api_contract.json", __DIR__)

    cond do
      is_binary(env) and env != "" -> env
      File.exists?(sibling) -> sibling
      true -> nil
    end
  end
end
