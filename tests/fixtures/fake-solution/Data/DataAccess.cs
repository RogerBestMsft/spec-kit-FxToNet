namespace Data;

public static class DataAccess
{
    public static string Read() => Core.CoreUtil.Stamp() + ":data";
}
