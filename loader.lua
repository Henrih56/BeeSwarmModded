-- BSS AutoFarm Loader v5.1
game.StarterGui:SetCore("SendNotification",{Title="BSS AutoFarm";Text="Carregando script completo...";Duration=3})

local base="https://raw.githubusercontent.com/Henrih56/BeeSwarmModded/main/"
local success,err=pcall(function()
	local script=game:HttpGet(base.."script_ultra_min.lua")
	loadstring(script)()
end)

if not success then
	game.StarterGui:SetCore("SendNotification",{Title="BSS AutoFarm ERRO";Text=tostring(err);Duration=10})
	warn("[BSS AutoFarm] Erro:",err)
end
