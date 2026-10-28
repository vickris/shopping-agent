defmodule DealAgent.Repo.Migrations.AddBeamAgentEvidence do
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE IF NOT EXISTS beam_agent_runs (
      run_key varchar(22) PRIMARY KEY,
      started_at_ms bigint NOT NULL,
      expires_at_ms bigint NOT NULL,
      outcome text CHECK (outcome IN ('ok', 'error')),
      execution_status text CHECK (execution_status IN ('finished', 'failed')),
      verification_status text CHECK (verification_status IN ('passed', 'failed', 'not_run')),
      error_type text CHECK (error_type IN (
        'startup_failed', 'verification_failed', 'execution_failed',
        'runner_crashed', 'execution_timeout', 'unknown_tool',
        'max_iterations_reached', 'max_tool_calls_reached',
        'max_execution_time_reached', 'max_context_messages_exceeded',
        'context_limit_too_small'
      )),
      iterations bigint CHECK (iterations >= 0),
      tool_calls bigint CHECK (tool_calls >= 0),
      finished_at_ms bigint,
      trace_status text CHECK (trace_status IN ('complete', 'incomplete')),
      gap_count bigint CHECK (gap_count >= 0)
    )
    """

    execute """
    CREATE INDEX IF NOT EXISTS beam_agent_runs_completed_idx
      ON beam_agent_runs (finished_at_ms DESC, run_key DESC)
      WHERE finished_at_ms IS NOT NULL
    """

    execute """
    CREATE INDEX IF NOT EXISTS beam_agent_runs_expiry_idx
      ON beam_agent_runs (expires_at_ms)
    """

    execute """
    CREATE TABLE IF NOT EXISTS beam_agent_trace_steps (
      run_key varchar(22) NOT NULL REFERENCES beam_agent_runs(run_key) ON DELETE CASCADE,
      sequence bigint NOT NULL CHECK (sequence >= 0),
      type text NOT NULL CHECK (type IN (
        'model_call', 'model_finished', 'tool_requested', 'tool_started',
        'tool_completed', 'tool_failed', 'context_compressed', 'finished', 'failed'
      )),
      iteration bigint NOT NULL CHECK (iteration >= 0),
      at_ms bigint NOT NULL,
      PRIMARY KEY (run_key, sequence)
    )
    """

    execute """
    ALTER TABLE beam_agent_runs
      ADD COLUMN IF NOT EXISTS input_tokens bigint CHECK (input_tokens >= 0),
      ADD COLUMN IF NOT EXISTS output_tokens bigint CHECK (output_tokens >= 0),
      ADD COLUMN IF NOT EXISTS reported_model_calls bigint CHECK (reported_model_calls >= 0),
      ADD COLUMN IF NOT EXISTS unreported_model_calls bigint CHECK (unreported_model_calls >= 0),
      ADD COLUMN IF NOT EXISTS usage_status text CHECK (usage_status IN ('reported', 'partial', 'unavailable')),
      ADD COLUMN IF NOT EXISTS cost_micro_usd bigint CHECK (cost_micro_usd >= 0),
      ADD COLUMN IF NOT EXISTS cost_status text CHECK (cost_status IN ('known', 'unknown_usage', 'unknown_price')),
      ADD COLUMN IF NOT EXISTS price_version bigint CHECK (price_version > 0)
    """
  end

  def down do
    execute "DROP TABLE beam_agent_trace_steps"
    execute "DROP TABLE beam_agent_runs"
  end
end
