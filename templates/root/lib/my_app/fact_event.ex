defprotocol MyApp.FactEvent do
  @doc "Turns a domain event struct into a Fact-ready map with `:type`, `:data` and `:tags`."
  def to_fact(event)
end
