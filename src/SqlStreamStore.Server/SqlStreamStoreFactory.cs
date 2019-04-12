using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Npgsql;
using Serilog;
using SqlStreamStore.Infrastructure;

namespace SqlStreamStore.Server
{
    internal class SqlStreamStoreFactory
    {
        private readonly SqlStreamStoreServerConfiguration _configuration;

        private delegate Task<IStreamStore> CreateStreamStore(
            string connectionString,
            string schema,
            CancellationToken cancellationToken);

        private const string postgres = nameof(postgres);
        private const string mssql = nameof(mssql);
        private const string inmemory = nameof(inmemory);

        private static readonly IDictionary<string, CreateStreamStore> s_factories
            = new Dictionary<string, CreateStreamStore>
            {
                [inmemory] = CreateInMemoryStreamStore,
                [postgres] = CreatePostgresStreamStore,
                [mssql] = CreateMssqlStreamStore
            };

        public SqlStreamStoreFactory(SqlStreamStoreServerConfiguration configuration)
        {
            if (configuration == null)
            {
                throw new ArgumentNullException(nameof(configuration));
            }

            _configuration = configuration;
        }

        public Task<IStreamStore> Create(CancellationToken cancellationToken = default)
        {
            var provider = _configuration.Provider?.ToLowerInvariant()
                           ?? inmemory;

            Log.Information("Creating stream store for provider {provider}", provider);

            if (!s_factories.TryGetValue(provider, out var factory))
            {
                throw new InvalidOperationException($"No provider factory for provider '{provider}' found.");
            }

            return factory(_configuration.ConnectionString, _configuration.Schema, cancellationToken);
        }

        private static Task<IStreamStore> CreateInMemoryStreamStore(
            string connectionString,
            string schema,
            CancellationToken cancellationToken)
            => Task.FromResult<IStreamStore>(new InMemoryStreamStore());

        private static async Task<IStreamStore> CreateMssqlStreamStore(
            string connectionString,
            string schema,
            CancellationToken cancellationToken)
        {
            var connectionStringBuilder = new SqlConnectionStringBuilder(connectionString);
            var settings = new MsSqlStreamStoreV3Settings(connectionString);

            if (schema != null)
            {
                settings.Schema = schema;
            }

            var streamStore = new MsSqlStreamStoreV3(settings);

            try
            {
                using (var connection = new SqlConnection(new SqlConnectionStringBuilder(connectionString)
                {
                    InitialCatalog = "master"
                }.ConnectionString))
                {
                    await connection.OpenAsync(cancellationToken).NotOnCapturedContext();

                    using (var command = new SqlCommand(
                        $@"
IF  NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'{connectionStringBuilder.InitialCatalog}')
BEGIN
    CREATE DATABASE [{connectionStringBuilder.InitialCatalog}]
END;
",
                        connection))
                    {
                        await command.ExecuteNonQueryAsync(cancellationToken).NotOnCapturedContext();
                    }
                }

                await streamStore.CreateSchemaIfNotExists(cancellationToken);
            }
            catch (SqlException ex)
            {
                SchemaCreationFailed(streamStore.GetSchemaCreationScript, ex);
                throw;
            }

            return streamStore;
        }

        private static async Task<IStreamStore> CreatePostgresStreamStore(
            string connectionString,
            string schema,
            CancellationToken cancellationToken)
        {
            var connectionStringBuilder = new NpgsqlConnectionStringBuilder(connectionString);
            var settings = new PostgresStreamStoreSettings(connectionString);

            if (schema != null)
            {
                settings.Schema = schema;
            }

            var streamStore = new PostgresStreamStore(settings);

            try
            {
                using (var connection = new NpgsqlConnection(new NpgsqlConnectionStringBuilder(connectionString)
                {
                    Database = null
                }.ConnectionString))
                {
                    await connection.OpenAsync(cancellationToken).NotOnCapturedContext();

                    async Task<bool> DatabaseExists()
                    {
                        using (var command = new NpgsqlCommand(
                            $"SELECT 1 FROM pg_database WHERE datname = '{connectionStringBuilder.Database}'",
                            connection))
                        {
                            return await command.ExecuteScalarAsync(cancellationToken).NotOnCapturedContext()
                                   != null;
                        }
                    }

                    if (!await DatabaseExists())
                    {
                        using (var command = new NpgsqlCommand(
                            $"CREATE DATABASE {connectionStringBuilder.Database}",
                            connection))
                        {
                            await command.ExecuteNonQueryAsync(cancellationToken).NotOnCapturedContext();
                        }
                    }

                    await streamStore.CreateSchemaIfNotExists(cancellationToken);
                }
            }
            catch (NpgsqlException ex)
            {
                SchemaCreationFailed(streamStore.GetSchemaCreationScript, ex);
                throw;
            }

            return streamStore;
        }

        private static void SchemaCreationFailed(Func<string> getSchemaCreationScript, Exception ex)
            => Log.Warning(
                new StringBuilder()
                    .Append("Could not create schema: {ex}")
                    .AppendLine()
                    .Append(
                        "Does your connection string have enough permissions? If not, run the following sql script as a privileged user:")
                    .AppendLine()
                    .Append("{script}")
                    .ToString(),
                ex,
                getSchemaCreationScript());
    }
}