defmodule OfficeGraph.TestSupport.VerificationGraph do
  @moduledoc false

  def build(signal, task, review_finding, verification_check) do
    %{
      signal: signal,
      task: task,
      review_finding: review_finding,
      verification_check: verification_check
    }
  end
end
