defmodule GhWebhookPlug do
  import Plug.Conn
  require Logger

  def init(options) do
    options
  end

  def call(conn, options) do
    path = options[:path]
    case conn.request_path do
      ^path ->
        secret = options[:secret] || get_secret
        {module, function} = get_module_function_from_opts(options[:action])
        {:ok, payload, _conn} = read_body(conn)
        [signature_in_header] = get_req_header(conn, "x-hub-signature")
        [event_in_header] = get_req_header(conn, "x-github-event")
        case to_string(event_in_header) do
          "push" ->
            if verify_signature(payload, secret, signature_in_header) do
              apply(module, function, [payload])
              conn |> send_resp(200, "OK") |> halt
            else
              conn |> send_resp(403, "Forbidden") |> halt
            end
          _event ->
            conn
        end
      _ -> conn
    end
  end

  def get_module_function_from_opts({module, function} = _action) do
    {module, function}
  end

  def get_module_function_from_opts(_) do
    raise "Action for Github webhook should be a tuple {<module>, <function>}, example: {__MODULE__, :gh_webhook_handler}"
  end

  defp verify_signature(payload, secret, signature_in_header) do
    signature = "sha1=" <> (:crypto.hmac(:sha, secret, payload) |> Base.encode16(case: :lower))
    Plug.Crypto.secure_compare(signature, signature_in_header)
  end

  defp get_secret do
    case(System.get_env("GH_WEBHOOK_SECRET") || Application.fetch_env(:gh_webhook_plug, :secret)) do
      :error ->
        Logger.warn "Github webhook secret is not configured."
        ""
      secret -> secret
    end
  end
end
