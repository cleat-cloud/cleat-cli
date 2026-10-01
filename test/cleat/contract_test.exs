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
end
