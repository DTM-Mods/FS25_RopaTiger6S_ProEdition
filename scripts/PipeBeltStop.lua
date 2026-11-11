--- Stops the unloading belts on every player's screen when unloading ends.
--
-- The base game switches unloading off without telling the other players when the tank runs empty,
-- when the vehicle is deactivated and when the engine is turned off (Dischargeable calls
-- setDischargeState(OFF, true), noEventSend). On a server the clients then never hear "OFF", so the
-- pipe and bunker belt animations keep scrolling. Here the server always sends the OFF event.

PipeBeltStop = {}

function PipeBeltStop.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Dischargeable, specializations)
end

function PipeBeltStop.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setDischargeState", PipeBeltStop.setDischargeState)
end

function PipeBeltStop:setDischargeState(superFunc, state, noEventSend)
    if noEventSend and state == Dischargeable.DISCHARGE_STATE_OFF and self.isServer then
        noEventSend = false
    end
    return superFunc(self, state, noEventSend)
end
