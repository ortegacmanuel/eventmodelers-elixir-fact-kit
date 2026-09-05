defprotocol MyApp.FactEvent do
  @doc "Convierte un evento de dominio en un mapa listo para Fact: `:type`, `:data` y `:tags`."
  def to_fact(event)
end
