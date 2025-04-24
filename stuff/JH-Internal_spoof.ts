import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import * as sql from 'mssql';
import { isValidRequest, validateDateRange } from '../shared/validation';

interface TimeSeriesEvent {
  timeStamp: string;
  value: number;
}

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

interface ErrorResponse {
  errorCode: string;
  message: string;
}

// Function handler for v4 API
export async function juliaHubInternal(
  request: HttpRequest,
  context: InvocationContext
): Promise<HttpResponseInit> {
  context.log('JuliaHub_Internal HTTP trigger function processed a request.');

  try {
    // Validate request payload
    const requestBody = await request.json() as RequestBody;
    if (!requestBody) {
      return { status: 400, body: 'Request body is required' };
    }

    const { tags, startDate, endDate, appContextGuid } = requestBody;

    // Validate request schema
    if (!isValidRequest(requestBody)) {
      const errorResponse: ErrorResponse = {
        errorCode: 'JH-4001',
        message: 'Invalid request schema. Please check API documentation.'
      };
      return {
        status: 422,
        jsonBody: errorResponse
      };
    }

    // Validate date range
    const dateRangeError = validateDateRange(startDate, endDate);
    if (dateRangeError) {
      const errorResponse: ErrorResponse = {
        errorCode: 'JH-4002',
        message: dateRangeError
      };
      return {
        status: 422,
        jsonBody: errorResponse
      };
    }

    // Connect to SQL and execute parameterized query
    const pool = new sql.ConnectionPool(process.env.SQL_CONN as string);
    await pool.connect();

    // Extract tag IDs for the IN clause
    const tagIds = tags.map((tag) => tag.tagId);

    const result = await pool
      .request()
      .input('startDate', sql.DateTime2, new Date(startDate))
      .input('endDate', sql.DateTime2, new Date(endDate))
      .query(
        `SELECT TagId, TimeStamp, Value 
         FROM dbo.TimeSeries 
         WHERE TagId IN (${tagIds.join(',')})
         AND TimeStamp BETWEEN @startDate AND @endDate
         ORDER BY TagId, TimeStamp ASC`
      );

    // Group results by tag
    const responsePayload: TagResponse[] = tags.map((tag) => ({
      tagName: tag.tagName,
      tagId: tag.tagId,
      appContextGuid,
      events: result.recordset
        .filter((record) => record.TagId === tag.tagId)
        .map((record) => ({
          timeStamp: record.TimeStamp.toISOString(),
          value: record.Value,
        })),
    }));

    // Record audit entry
    const status = result.recordset.length > 0 ? 'S' : 'Z'; // S = Success with data, Z = Zero rows
    await pool
      .request()
      .input('appContextGuid', sql.UniqueIdentifier, appContextGuid)
      .input('functionName', sql.NVarChar(50), 'JuliaHub_Internal')
      .input('startDateUtc', sql.DateTime2, new Date(startDate))
      .input('endDateUtc', sql.DateTime2, new Date(endDate))
      .input('rowTotal', sql.Int, result.recordset.length)
      .input('status', sql.Char(1), status)
      .query(
        `INSERT INTO JuliaHub_Audit 
         (appContextGuid, functionName, startDateUtc, endDateUtc, rowTotal, status, runTimestampUtc) 
         VALUES 
         (@appContextGuid, @functionName, @startDateUtc, @endDateUtc, @rowTotal, @status, SYSUTCDATETIME())`
      );

    await pool.close();

    // Return appropriate response code
    if (result.recordset.length > 0) {
      return {
        status: 200,
        jsonBody: responsePayload,
      };
    } else {
      return {
        status: 204
      };
    }
  } catch (error) {
    context.error('Error in JuliaHub_Internal function:', error);

    // Record error in audit log
    try {
      const pool = new sql.ConnectionPool(process.env.SQL_CONN as string);
      await pool.connect();

      let requestBody: RequestBody | undefined;
      try {
        requestBody = await request.json() as RequestBody;
      } catch {
        // Ignore parsing errors for error handling
      }
      
      const defaultGuid = '00000000-0000-0000-0000-000000000000';

      await pool
        .request()
        .input('appContextGuid', sql.UniqueIdentifier, requestBody?.appContextGuid || defaultGuid)
        .input('functionName', sql.NVarChar(50), 'JuliaHub_Internal')
        .input('startDateUtc', sql.DateTime2, requestBody?.startDate ? new Date(requestBody.startDate) : new Date())
        .input('endDateUtc', sql.DateTime2, requestBody?.endDate ? new Date(requestBody.endDate) : new Date())
        .input('rowTotal', sql.Int, 0)
        .input('status', sql.Char(1), 'F') // F = Failure
        .input('lastError', sql.NVarChar(4000), error instanceof Error ? error.message : String(error))
        .query(
          `INSERT INTO JuliaHub_Audit 
           (appContextGuid, functionName, startDateUtc, endDateUtc, rowTotal, status, lastError, runTimestampUtc) 
           VALUES 
           (@appContextGuid, @functionName, @startDateUtc, @endDateUtc, @rowTotal, @status, @lastError, SYSUTCDATETIME())`
        );

      await pool.close();
    } catch (auditError) {
      context.error('Failed to record audit entry for error:', auditError);
    }

    // Return appropriate error response
    const errorResponse: ErrorResponse = {
      errorCode: 'JH-5001',
      message: 'Internal server error occurred'
    };
    
    return {
      status: 500,
      jsonBody: errorResponse
    };
  }
}

// For v4 direct binding
app.http('juliaHubInternal', {
  methods: ['POST'],
  authLevel: 'function',
  handler: juliaHubInternal,
});

// For v3 function.json compatibility
export default async function httpTrigger(context: any, req: any) {
  try {
    const request = {
      method: req.method,
      url: req.url,
      headers: new Headers(req.headers),
      body: req.body,
      json: async () => req.body
    };

    const response = await juliaHubInternal(request as any, context);
    
    context.res = {
      status: response.status,
      body: response.jsonBody || response.body
    };
  } catch (error) {
    context.log.error('Error in httpTrigger:', error);
    context.res = {
      status: 500,
      body: {
        errorCode: 'JH-5002',
        message: 'Internal server error in trigger handler'
      }
    };
  }
} 