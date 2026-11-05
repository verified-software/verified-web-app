object TenantSmoke:
  import TenantCore.*
  def main(args: Array[String]): Unit =
    val keys = (0 to 3).toList.flatMap(n => (0 until (1 << n)).map(i => (0 until n).map(j => ((i >> j) & 1) == 1).toList))
    val members = for key <- keys; role <- List(Role.Reader, Role.Writer) yield Principal.Member(key, role)
    var checked = 0
    for principal <- Principal.Anonymous :: members; target <- keys; action <- List(Action.Read, Action.Write) do
      val expected = principal match
        case Principal.Anonymous => false
        case Principal.Member(source, role) => source == target && (action == Action.Read || role == Role.Writer)
      assert(permitted(principal, target, action) == expected, s"permission mismatch: $principal $target $action")
      assert(guarded(principal, action, Scoped.Resource(target, "secret")) == (if expected then Some("secret") else None))
      checked += 1
    println(s"Scala shared tenant core: $checked cases passed")
