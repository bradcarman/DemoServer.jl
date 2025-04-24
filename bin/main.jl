using HTTP, Sockets, UUIDs, JSON2

# modified Animal struct to associate with specific user
mutable struct Animal
    id::Int
    userId::UUID
    type::String
    name::String
end

# use a plain `Dict` as a "data store"
const ANIMALS = Dict{Int, Animal}()
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
HTTP.@register(ANIMAL_ROUTER, "POST", "/api/zoo/v1/animals", createAnimal)
# note the use of `*` to capture the path segment "variable" animal id
HTTP.@register(ANIMAL_ROUTER, "GET", "/api/zoo/v1/animals/*", getAnimal)
HTTP.@register(ANIMAL_ROUTER, "PUT", "/api/zoo/v1/animals", updateAnimal)
HTTP.@register(ANIMAL_ROUTER, "DELETE", "/api/zoo/v1/animals/*", deleteAnimal)

# Start the server
HTTP.serve(ANIMAL_ROUTER, ip"0.0.0.0", parse(Int, get(ENV, "PORT", "8080")))
