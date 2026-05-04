namespace Web;

public static class Endpoint
{
    public static string Handle() => Data.DataAccess.Read();
}
