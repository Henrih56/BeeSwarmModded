-- BSS AutoFarm Loader v5.1
game.StarterGui:SetCore("SendNotification",{Title="BSS AutoFarm";Text="Carregando (parte 1/2)...";Duration=2})

local base="https://raw.githubusercontent.com/Henrih56/BeeSwarmModded/main/"
local success,err=pcall(function()
	local part1=game:HttpGet(base.."part1.lua")
	local part2=game:HttpGet(base.."part2.lua")
	game.StarterGui:SetCore("SendNotification",{Title="BSS AutoFarm";Text="Executando script...";Duration=2})
	loadstring(part1..part2)()
end)

if not success then
	game.StarterGui:SetCore("SendNotification",{Title="BSS AutoFarm ERRO";Text=tostring(err);Duration=10})
	warn("[BSS AutoFarm] Erro:",err)
end
