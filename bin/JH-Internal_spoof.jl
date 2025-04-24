using HTTP
using JSON3
using ODBC
using Dates

function validate_request(body::Dict)
    haskey(body, "tags") && haskey(body, "startDate") &&
    haskey(body, "endDate") && haskey(body, "appContextGuid")
end

function validate_date_range(start_date::String, end_date::String)
    try
        sd = DateTime(start_date)
        ed = DateTime(end_date)
        if sd > ed
            return "Start date is after end date"
        end
        return nothing
    catch e
        return "Invalid date format"
    end
end

function handle_request(req::HTTP.Request)
    try
        body = JSON3.read(String(req.body))
        if !validate_request(body)
            return HTTP.Response(422, JSON3.write(Dict(
                "errorCode" => "JH-4001",
                "message" => "Invalid request schema"
            )))
        end

        date_error = validate_date_range(body["startDate"], body["endDate"])
        if date_error !== nothing
            return HTTP.Response(422, JSON3.write(Dict(
                "errorCode" => "JH-4002",
                "message" => date_error
            )))
        end

        tags = body["tags"]
        tag_ids = join([tag["tagId"] for tag in tags], ",")

        conn = ODBC.Connection(ENV["SQL_CONN"])

        query = """
            SELECT TagId, TimeStamp, Value
            FROM dbo.TimeSeries
            WHERE TagId IN ($tag_ids)
            AND TimeStamp BETWEEN ? AND ?
            ORDER BY TagId, TimeStamp ASC
        """

        result = ODBC.query(conn, query, DateTime(body["startDate"]), DateTime(body["endDate"]))
        
        grouped = Dict{Int, Vector{Dict}}()
        for row in result
            push!(get!(grouped, row[:TagId], []), Dict(
                "timeStamp" => Dates.format(row[:TimeStamp], "yyyy-mm-ddTHH:MM:SSZ"),
                "value" => row[:Value]
            ))
        end

        response = [Dict(
            "tagName" => tag["tagName"],
            "tagId" => tag["tagId"],
            "appContextGuid" => body["appContextGuid"],
            "events" => get(grouped, tag["tagId"], [])
        ) for tag in tags]

        # Add audit logging if needed here

        HTTP.Response(200, JSON3.write(response))
    catch e
        HTTP.Response(500, JSON3.write(Dict(
            "errorCode" => "JH-5001",
            "message" => "Internal server error occurred",
            "details" => sprint(showerror, e)
        )))
    end
end
