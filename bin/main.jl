using OpenSSL, HTTP, Sockets, UUIDs, JSON2

# modified Animal struct to associate with specific user
mutable struct Animal
    type::String
    name::String
end

struct TimeSeriesEvent
    timeStamp::String
    value::Number
end

#=

interface TimeSeriesEvent {
  timeStamp: string;
  value: number;
}

=#

struct TagResponse
    tagName::String
    tagID::Int
    appContextGuid::String
    events::Vector{TimeSeriesEvent}
end

#=

interface TagResponse {
  tagName: string;
  tagId: number;
  appContextGuid: string;
  events: TimeSeriesEvent[];
}

interface RequestBody {
  tags: Array<{ tagName: string; tagId: number }>;
  startDate: string;
  endDate: string;
  appContextGuid: string;
}

=#

struct TagItem
    tagName::String
    tagId::Number
end
struct RequestBody
    # tags::Vector{TagItem}
    startDate::String
    endDate::String
    appContextGuid::String
end

function helixRequest(req::HTTP.Request)
    try
        @show req
        req_body = JSON2.read(IOBuffer(HTTP.payload(req)), RequestBody)
        # run model and return data...
    
        @show req_body
        # response = [TagResponse(tag.tagName, tag.tagId, req_body.appContextGuid, [TimeSeriesEvent("4/24/2025 - 4:05PM", 0.0)]) for tag in req_body.tags]
      
        response = [TagResponse("brad", 01234, req_body.appContextGuid, [TimeSeriesEvent("4/24/2025 - 4:05PM", 0.0)])]
        @show response
    
        return HTTP.Response(200, JSON2.write(response))
    catch err
        println(err)
        return HTTP.Response(404)
    end

end

#=
"tags": [
    {
      "tagName": "SW_P1_Efficiency_1",
      "tagId": 11708159
    },
    {
      "tagName": "SW_P2_Current_1",
      "tagId": 11708160
    }
  ],
=#

json = """{
  "startDate": "2025-03-19T04:00:00.000Z",
  "endDate": "2025-03-19T05:00:00.000Z",
  "appContextGuid": "6557BEFD-4A2F-4AC6-B333-130A0EC25B20"
}"""

req_body = JSON2.read(IOBuffer(json), RequestBody)


# use a plain `Dict` as a "data store"
const ANIMALS = Dict{Int, Animal}()
ANIMALS[1] = Animal("Dog","Brad")
ANIMALS[2] = Animal("Cat","Siva")
ANIMALS[3] = Animal("Fish","Marcus")
const NEXT_ID = Ref(0)
function getNextId()
    id = NEXT_ID[]
    NEXT_ID[] += 1
    return id
end

# "service" functions to actually do the work
function createAnimal(req::HTTP.Request)
    animal = JSON2.read(IOBuffer(HTTP.payload(req)), Animal)
    animal.id = getNextId()
    ANIMALS[animal.id] = animal
    return HTTP.Response(200, JSON2.write(animal))
end

function getAnimal(req::HTTP.Request)
    animalId = HTTP.URIs.splitpath(req.target)[5] # /api/zoo/v1/animals/10, get 10
    id = parse(Int, animalId)
    if haskey(ANIMALS, id)
        return HTTP.Response(200, JSON2.write(ANIMALS[id]))
    else
        return HTTP.Response(404)
    end
end

function updateAnimal(req::HTTP.Request)
    animal = JSON2.read(IOBuffer(HTTP.payload(req)), Animal)
    ANIMALS[animal.id] = animal
    return HTTP.Response(200, JSON2.write(animal))
end

function deleteAnimal(req::HTTP.Request)
    animalId = HTTP.URIs.splitpath(req.target)[5] # /api/zoo/v1/animals/10, get 10
    delete!(ANIMALS, parse(Int, animal.id))
    return HTTP.Response(200)
end

# define REST endpoints to dispatch to "service" functions
const ANIMAL_ROUTER = HTTP.Router()
HTTP.register!(ANIMAL_ROUTER, "POST", "/api/zoo/v1/animals", createAnimal)
# note the use of `*` to capture the path segment "variable" animal id
HTTP.register!(ANIMAL_ROUTER, "GET", "/api/zoo/v1/animals/*", getAnimal)
HTTP.register!(ANIMAL_ROUTER, "PUT", "/api/zoo/v1/animals", updateAnimal)
HTTP.register!(ANIMAL_ROUTER, "DELETE", "/api/zoo/v1/animals/*", deleteAnimal)

HTTP.register!(ANIMAL_ROUTER, "POST", "/api/helix", helixRequest)
HTTP.register!(ANIMAL_ROUTER, "GET", "/**", ()->HTTP.Response(404, "Not Found"))

# Start the server
HTTP.serve(ANIMAL_ROUTER, ip"0.0.0.0", parse(Int, get(ENV, "PORT", "8080")))



